import Foundation
import CoreLocation

enum Geo {
    static let earthRadius = 6_371_000.0

    static func destination(from start: CLLocationCoordinate2D, distance: Double, bearing: Double) -> CLLocationCoordinate2D {
        let d = distance / earthRadius
        let t = bearing * .pi / 180
        let p1 = start.latitude * .pi / 180
        let l1 = start.longitude * .pi / 180
        let p2 = asin(sin(p1) * cos(d) + cos(p1) * sin(d) * cos(t))
        let l2 = l1 + atan2(sin(t) * sin(d) * cos(p1), cos(d) - sin(p1) * sin(p2))
        var lon = l2 * 180 / .pi
        lon = (lon + 540).truncatingRemainder(dividingBy: 360) - 180
        return CLLocationCoordinate2D(latitude: p2 * 180 / .pi, longitude: lon)
    }

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let toR = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * toR, dLon = (b.longitude - a.longitude) * toR
        let h = pow(sin(dLat / 2), 2) + cos(a.latitude * toR) * cos(b.latitude * toR) * pow(sin(dLon / 2), 2)
        return 2 * earthRadius * asin(sqrt(h))
    }

    /// Waypoints on a circle that passes through `home`; the circle's centre lies in direction `bearing`.
    static func circlePoints(home: CLLocationCoordinate2D, radius: Double, bearing: Double, count: Int = 4) -> [CLLocationCoordinate2D] {
        let center = destination(from: home, distance: radius, bearing: bearing)
        return (1...count).map { k in
            destination(from: center, distance: radius, bearing: bearing + 180 + Double(k) * 360 / Double(count + 1))
        }
    }

    /// Global pixel position in the Web Mercator tile grid.
    static func worldPixel(_ c: CLLocationCoordinate2D, zoom: Int) -> (x: Double, y: Double) {
        let n = 256 * pow(2, Double(zoom))
        let s = sin(c.latitude * .pi / 180)
        return ((c.longitude + 180) / 360 * n, (0.5 - log((1 + s) / (1 - s)) / (4 * .pi)) * n)
    }
}

/// Google encoded polyline (precision 5) – compact storage of routes.
enum Polyline {
    static func encode(_ coords: [CLLocationCoordinate2D]) -> String {
        var out = ""
        var pLat = 0, pLon = 0
        func enc(_ value: Int) {
            var v = value < 0 ? ~(value << 1) : (value << 1)
            while v >= 0x20 {
                out.unicodeScalars.append(UnicodeScalar(UInt8((0x20 | (v & 0x1f)) + 63)))
                v >>= 5
            }
            out.unicodeScalars.append(UnicodeScalar(UInt8(v + 63)))
        }
        for c in coords {
            let lat = Int((c.latitude * 1e5).rounded()), lon = Int((c.longitude * 1e5).rounded())
            enc(lat - pLat); enc(lon - pLon)
            pLat = lat; pLon = lon
        }
        return out
    }

    static func decode(_ s: String) -> [CLLocationCoordinate2D] {
        let bytes = Array(s.utf8)
        var out: [CLLocationCoordinate2D] = []
        var i = 0, lat = 0, lon = 0
        func next() -> Int? {
            var result = 0, shift = 0
            while i < bytes.count {
                let b = Int(bytes[i]) - 63
                i += 1
                result |= (b & 0x1f) << shift
                shift += 5
                if b < 0x20 { return (result & 1) != 0 ? ~(result >> 1) : (result >> 1) }
            }
            return nil
        }
        while i < bytes.count {
            guard let dLat = next(), let dLon = next() else { break }
            lat += dLat; lon += dLon
            out.append(CLLocationCoordinate2D(latitude: Double(lat) / 1e5, longitude: Double(lon) / 1e5))
        }
        return out
    }
}
