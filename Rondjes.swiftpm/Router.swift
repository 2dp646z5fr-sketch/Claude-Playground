import Foundation
import CoreLocation

struct RouteResult {
    var coords: [CLLocationCoordinate2D]
    var elevations: [Double]?
    var meters: Double
    var ascend: Double?
    var router: String
    var green: Double? = nil
    var urban: Double? = nil
    var bearing: Double = 0
    var radius: Double = 0
    var plain = false
    var failed = false
}

enum RoutingError: LocalizedError {
    case unroutable(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .unroutable: return "Deze punten zijn niet over paden te verbinden."
        case .server(let m): return "De routeplanner gaf een fout: \(m)"
        }
    }
}

/// Talks to BRouter (nature profile) with OSRM (plain walking) as fallback.
actor Router {
    static let shared = Router()

    private var profileId: String?
    private var lastRequest = Date.distantPast
    private var brouterFailures = 0

    /// Prefer paths/tracks, forest and water; avoid built-up areas, noise and big roads.
    static let profile = """
    ---context:global
    assign validForFoot   = true
    assign validForBikes  = false
    assign validForCars   = false
    assign turnInstructionMode = 0
    assign processUnusedTags = false
    assign downhillcost = 0
    assign uphillcost = 0

    ---context:way
    assign forbidden = or highway= or highway=motorway|motorway_link|trunk|trunk_link|construction|proposed or foot=no|private access=no|private
    assign base = switch highway=path|footway|track|bridleway 1.3
                  switch highway=pedestrian|living_street|cycleway 1.6
                  switch highway=steps 1.9
                  switch highway=residential|service|unclassified|road 2.0
                  switch highway=tertiary|tertiary_link 2.8
                  switch highway=secondary|secondary_link 3.6
                  switch highway=primary|primary_link 4.5 3.0
    assign surfacebonus = switch surface=unpaved|ground|dirt|grass|gravel|fine_gravel|compacted|earth|sand 0.9 1.0
    assign forest = switch estimated_forest_class=5|6 0.62 switch estimated_forest_class=3|4 0.75 switch estimated_forest_class=1|2 0.88 1.0
    assign river = switch estimated_river_class=4|5|6 0.85 switch estimated_river_class=1|2|3 0.93 1.0
    assign town = switch estimated_town_class=5|6 1.7 switch estimated_town_class=3|4 1.4 switch estimated_town_class=1|2 1.15 1.0
    assign noise = switch estimated_noise_class=5|6 1.5 switch estimated_noise_class=3|4 1.25 1.0
    assign costfactor = if forbidden then 10000 else max 1 multiply base multiply surfacebonus multiply forest multiply river multiply town noise
    assign uphillcostfactor = costfactor
    assign downhillcostfactor = costfactor

    ---context:node
    assign initialcost = 0

    """

    /// At most one request per second: these are free community servers.
    private func polite() async {
        let wait = 1.0 - Date().timeIntervalSince(lastRequest)
        lastRequest = Date().addingTimeInterval(max(0, wait))
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
    }

    private func ensureProfile() async throws -> String {
        if let profileId { return profileId }
        await polite()
        var req = URLRequest(url: URL(string: "https://brouter.de/brouter/profile")!)
        req.httpMethod = "POST"
        req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(Self.profile.utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        struct Reply: Decodable { let profileid: String?; let error: String? }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        guard let id = reply.profileid, reply.error == nil else {
            throw RoutingError.server(reply.error ?? "profiel niet geaccepteerd")
        }
        profileId = id
        return id
    }

    private func brouter(_ points: [CLLocationCoordinate2D], retry: Bool = true) async throws -> RouteResult {
        let id = try await ensureProfile()
        await polite()
        let lonlats = points.map { String(format: "%.6f,%.6f", $0.longitude, $0.latitude) }.joined(separator: "|")
        var comps = URLComponents(string: "https://brouter.de/brouter")!
        comps.queryItems = [
            URLQueryItem(name: "lonlats", value: lonlats),
            URLQueryItem(name: "profile", value: id),
            URLQueryItem(name: "alternativeidx", value: "0"),
            URLQueryItem(name: "format", value: "geojson")
        ]
        let (data, response) = try await URLSession.shared.data(from: comps.url!)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status != 200 {
            let text = String(data: data, encoding: .utf8) ?? ""
            if retry, text.lowercased().contains("profile") {
                profileId = nil
                return try await brouter(points, retry: false)
            }
            if text.range(of: "island|not mapped|no track|not found|no route|operation killed",
                          options: [.regularExpression, .caseInsensitive]) != nil {
                throw RoutingError.unroutable(text)
            }
            throw RoutingError.server(text.isEmpty ? "HTTP \(status)" : String(text.prefix(120)))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]],
              let feature = features.first,
              let geometry = feature["geometry"] as? [String: Any],
              let raw = geometry["coordinates"] as? [[Double]],
              let props = feature["properties"] as? [String: Any] else {
            throw RoutingError.server("onverwacht antwoord")
        }
        let coords = raw.compactMap { $0.count >= 2 ? CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) : nil }
        let elevations = raw.allSatisfy { $0.count >= 3 } ? raw.map { $0[2] } : nil
        let meters = Double(props["track-length"] as? String ?? "") ?? 0
        let ascend = Double(props["filtered ascend"] as? String ?? "")
        return RouteResult(coords: coords, elevations: elevations, meters: meters, ascend: ascend, router: "brouter")
    }

    private func osrm(_ points: [CLLocationCoordinate2D]) async throws -> RouteResult {
        await polite()
        let path = points.map { String(format: "%.6f,%.6f", $0.longitude, $0.latitude) }.joined(separator: ";")
        let url = URL(string: "https://routing.openstreetmap.de/routed-foot/route/v1/foot/\(path)?overview=full&geometries=polyline&steps=false")!
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["code"] as? String) == "Ok",
              let routes = json["routes"] as? [[String: Any]],
              let first = routes.first,
              let geometry = first["geometry"] as? String,
              let distance = first["distance"] as? Double else {
            throw RoutingError.unroutable("geen route")
        }
        return RouteResult(coords: Polyline.decode(geometry), elevations: nil, meters: distance, ascend: nil, router: "osrm")
    }

    /// Nature route via BRouter; plain walking route if BRouter is unavailable (or when `plain` is set).
    func route(_ points: [CLLocationCoordinate2D], plain: Bool = false) async throws -> RouteResult {
        if !plain && brouterFailures < 3 {
            do {
                let r = try await brouter(points)
                brouterFailures = 0
                return r
            } catch let error as RoutingError {
                if case .unroutable = error { throw error }
                brouterFailures += 1
            } catch {
                brouterFailures += 1
            }
        }
        return try await osrm(points)
    }
}
