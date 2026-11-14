import Foundation
import MapKit

/// Builds a closed running loop that starts and ends at home, with a total
/// walking-route length as close as possible to the requested distance.
///
/// Idea: place a circle that passes through home, put a few waypoints on that
/// circle, and let Apple Maps route (on foot) home → P1 → … → Pn → home.
/// The circle radius is then scaled until the routed length matches the target.
struct LoopGenerator {
    enum GeneratorError: LocalizedError {
        case noRoute

        var errorDescription: String? {
            "Er kon geen looproute rond je huis worden gevonden. Probeer het opnieuw of kies een andere richting."
        }
    }

    /// Number of waypoints on the circle (excluding home).
    var waypointCount = 4
    /// Accept a loop when it is within this many metres of the target.
    var toleranceMeters = 150.0
    var maxIterations = 6
    /// Pause between routing requests to stay below Apple's rate limit (~50/min).
    var requestSpacing: Duration = .milliseconds(1300)

    /// - Parameters:
    ///   - bearing: direction (degrees) from home towards the centre of the loop.
    ///   - progress: optional callback with a short status text.
    func generate(home: CLLocationCoordinate2D,
                  targetMeters: Double,
                  bearing: Double,
                  progress: (@MainActor (String) -> Void)? = nil) async throws -> (coordinates: [CLLocationCoordinate2D], meters: Double) {
        // Roads are longer than the ideal circle; start with a factor of ~1.25.
        var radius = targetMeters / (2 * .pi * 1.25)
        var best: (coordinates: [CLLocationCoordinate2D], meters: Double)?
        var currentBearing = bearing
        var failures = 0

        var iteration = 0
        while iteration < maxIterations {
            try Task.checkCancellation()
            await progress?("Poging \(iteration + 1)…")

            let waypoints = circleWaypoints(home: home, radius: radius, bearing: currentBearing)
            let result: (coordinates: [CLLocationCoordinate2D], meters: Double)
            do {
                result = try await route(through: [home] + waypoints + [home])
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Probably a waypoint in water or somewhere unreachable: rotate.
                failures += 1
                if failures > 4 { break }
                currentBearing += 47
                continue
            }

            if best == nil || abs(result.meters - targetMeters) < abs(best!.meters - targetMeters) {
                best = result
            }
            if abs(result.meters - targetMeters) <= toleranceMeters { break }

            // Scale the circle by the error ratio (slightly damped).
            let ratio = targetMeters / max(result.meters, 1)
            radius *= pow(ratio, 0.9)
            iteration += 1
        }

        guard let best else { throw GeneratorError.noRoute }
        return best
    }

    private func circleWaypoints(home: CLLocationCoordinate2D, radius: Double, bearing: Double) -> [CLLocationCoordinate2D] {
        let center = Geo.destination(from: home, distance: radius, bearing: bearing)
        // Home lies on the circle at angle (bearing + 180) seen from the centre.
        let homeAngle = bearing + 180
        let n = waypointCount + 1
        return (1...waypointCount).map { k in
            let angle = homeAngle + Double(k) * 360 / Double(n)
            return Geo.destination(from: center, distance: radius, bearing: angle)
        }
    }

    private func route(through points: [CLLocationCoordinate2D]) async throws -> (coordinates: [CLLocationCoordinate2D], meters: Double) {
        var coordinates: [CLLocationCoordinate2D] = []
        var meters = 0.0

        for (from, to) in zip(points, points.dropFirst()) {
            let leg = try await walkingRoute(from: from, to: to)
            meters += leg.distance
            var legCoords = leg.polyline.coordinates
            if !coordinates.isEmpty, !legCoords.isEmpty { legCoords.removeFirst() }
            coordinates += legCoords
            try await Task.sleep(for: requestSpacing)
        }
        return (coordinates, meters)
    }

    private func walkingRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async throws -> MKRoute {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .walking
        request.requestsAlternateRoutes = false

        var attempts = 0
        while true {
            do {
                let response = try await MKDirections(request: request).calculate()
                guard let route = response.routes.first else { throw GeneratorError.noRoute }
                return route
            } catch let error as MKError where error.code == .loadingThrottled && attempts < 3 {
                // Apple limits the number of requests per minute; wait and retry.
                attempts += 1
                try await Task.sleep(for: .seconds(30))
            }
        }
    }
}

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
