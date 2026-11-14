import Foundation
import CoreLocation

enum Geo {
    static let earthRadius = 6_371_000.0

    /// Point reached when travelling `distance` metres from `start` on `bearing` degrees.
    static func destination(from start: CLLocationCoordinate2D, distance: Double, bearing: Double) -> CLLocationCoordinate2D {
        let δ = distance / earthRadius
        let θ = bearing * .pi / 180
        let φ1 = start.latitude * .pi / 180
        let λ1 = start.longitude * .pi / 180

        let φ2 = asin(sin(φ1) * cos(δ) + cos(φ1) * sin(δ) * cos(θ))
        let λ2 = λ1 + atan2(sin(θ) * sin(δ) * cos(φ1), cos(δ) - sin(φ1) * sin(φ2))

        return CLLocationCoordinate2D(latitude: φ2 * 180 / .pi,
                                      longitude: λ2 * 180 / .pi)
    }
}
