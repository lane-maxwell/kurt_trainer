import CoreLocation
import Foundation

/// A synthetic 10 km course (flat, a ~6% climb, descent, rollers) for trying the app without a GPX file.
enum DemoRoute {
    static let id = "demo"

    static func make() -> Route {
        let start = CLLocationCoordinate2D(latitude: 39.0, longitude: -105.5)
        let spacing = 10.0
        let count = 1001
        var coordinates: [CLLocationCoordinate2D] = []
        var elevations: [Double?] = []
        var heading = 30.0
        var position = start

        for index in 0..<count {
            let distance = Double(index) * spacing
            coordinates.append(position)
            elevations.append(2400 + elevationOffset(at: distance))

            // Gentle meandering so the map camera has something to follow.
            heading += sin(distance / 400) * 1.5
            position = step(from: position, meters: spacing, bearing: heading)
        }

        // Fixed, valid inputs: construction can only fail if the generator above is broken.
        return try! Route(id: id, name: "Demo Climb (synthetic)", coordinates: coordinates, elevations: elevations)
    }

    private static func elevationOffset(at distance: Double) -> Double {
        switch distance {
        case ..<1500:
            return 0
        case ..<5000:
            let x = distance - 1500
            return x * 0.06 + sin(x / 250) * 8
        case ..<7000:
            let top = 3500 * 0.06 + sin(3500 / 250.0) * 8
            return top - (distance - 5000) * 0.07
        default:
            let bottom = 3500 * 0.06 + sin(3500 / 250.0) * 8 - 2000 * 0.07
            return bottom + sin((distance - 7000) / 300) * 15
        }
    }

    private static func step(from origin: CLLocationCoordinate2D, meters: Double, bearing: Double) -> CLLocationCoordinate2D {
        let angular = meters / Geo.earthRadiusMeters
        let theta = bearing * .pi / 180
        let lat1 = origin.latitude * .pi / 180
        let lon1 = origin.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(theta))
        let lon2 = lon1 + atan2(sin(theta) * sin(angular) * cos(lat1), cos(angular) - sin(lat1) * sin(lat2))
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }
}
