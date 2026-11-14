import Foundation
import CoreLocation

/// Codable coordinate.
struct Coordinate: Codable, Hashable {
    var latitude: Double
    var longitude: Double

    init(_ c: CLLocationCoordinate2D) {
        latitude = c.latitude
        longitude = c.longitude
    }

    var cl: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

/// A generated loop for one distance (key: target distance in metres).
struct RunLoop: Codable, Identifiable {
    var target: Int                 // metres
    var meters: Int                 // routed length
    var polyline: String            // encoded polyline (precision 5)
    var elevations: [Double]?       // 80 samples along the route
    var ascend: Double?
    var green: Double?              // share of the route through nature / green / water (0…1)
    var urban: Double?              // share through built-up areas (0…1)
    var bearing: Double
    var router: String              // "brouter" or "osrm"
    var generatedAt: Date

    var id: Int { target }
    var coordinates: [CLLocationCoordinate2D] { Polyline.decode(polyline) }
}

/// The series of distances, e.g. 3 – 43 km per 0,5 km.
struct Series: Codable, Equatable {
    var from: Double = 3
    var to: Double = 43
    var step: Double = 0.5

    var distances: [Int] {
        var out: [Int] = []
        var i = 0
        while out.count <= 300 {
            let km = from + Double(i) * step
            if km > to + 1e-9 { break }
            out.append(Int((km * 1000).rounded()))
            i += 1
        }
        return out
    }
}

enum Fmt {
    static let nl = Locale(identifier: "nl_NL")

    static func number(_ v: Double, digits: Int = 1) -> String {
        v.formatted(.number.precision(.fractionLength(digits)).locale(nl))
    }

    /// "12,5" or "12,35" (two decimals only when needed).
    static func km(_ meters: Int) -> String {
        number(Double(meters) / 1000, digits: meters % 100 == 0 ? 1 : 2)
    }

    static func duration(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let h = total / 60, m = total % 60
        return h > 0 ? "\(h):\(String(format: "%02d", m)) u" : "\(m) min"
    }

    static func pace(_ p: Double) -> String {
        let m = Int(p), s = Int(((p - Double(m)) * 60).rounded())
        return "\(m):\(String(format: "%02d", s))"
    }

    /// Parses "12,5" or "12.5".
    static func parse(_ s: String) -> Double? {
        Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    /// Parses "5:30" or "5,5" minutes per km.
    static func parsePace(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.contains(":") {
            let parts = t.split(separator: ":").compactMap { Double($0) }
            guard parts.count == 2 else { return nil }
            return parts[0] + parts[1] / 60
        }
        return parse(t)
    }
}
