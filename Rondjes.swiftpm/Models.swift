import Foundation
import CoreLocation

/// Codable wrapper around a coordinate.
struct Coordinate: Codable, Hashable {
    var latitude: Double
    var longitude: Double

    init(_ c: CLLocationCoordinate2D) {
        latitude = c.latitude
        longitude = c.longitude
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// A generated running loop for one target distance.
struct RunLoop: Codable, Identifiable {
    /// Distance step in half kilometres (6 = 3,0 km … 86 = 43,0 km).
    var step: Int
    var actualMeters: Double
    var coordinates: [Coordinate]
    var generatedAt: Date

    var id: Int { step }
    var targetKm: Double { Double(step) / 2 }
    var actualKm: Double { actualMeters / 1000 }
}

enum Distances {
    /// 3,0 km t/m 43,0 km in stappen van 0,5 km.
    static let steps: [Int] = Array(6...86)

    static func km(_ step: Int) -> Double { Double(step) / 2 }

    static func label(_ step: Int) -> String {
        format(km: km(step))
    }

    static func format(km: Double, digits: Int = 1) -> String {
        km.formatted(.number.precision(.fractionLength(digits))) + " km"
    }
}
