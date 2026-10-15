import CoreLocation
import Foundation

struct RoutePoint: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let elevation: Double
    /// Distance along the route from the first point, in metres.
    let distance: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct RoutePosition: Equatable, Sendable {
    let coordinate: CLLocationCoordinate2D
    let elevation: Double
    /// Direction of travel, in degrees clockwise from north.
    let heading: Double

    static func == (lhs: RoutePosition, rhs: RoutePosition) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
            && lhs.elevation == rhs.elevation
            && lhs.heading == rhs.heading
    }
}

enum RouteError: Error, Equatable, LocalizedError {
    case tooFewPoints(Int)
    case zeroLength
    case invalidCoordinate(latitude: Double, longitude: Double)

    var errorDescription: String? {
        switch self {
        case let .tooFewPoints(count):
            "A route needs at least 2 track points; this one has \(count)."
        case .zeroLength:
            "All of this route's points are in the same place."
        case let .invalidCoordinate(latitude, longitude):
            "Invalid coordinate (\(latitude), \(longitude))."
        }
    }
}

/// A rideable course: a polyline with elevation, indexed by distance from the start.
struct Route: Identifiable, Sendable {
    /// Grade is measured across this span to smooth out GPS elevation noise.
    static let gradeWindowMeters = 50.0
    static let maximumGrade = 0.25

    let id: String
    let name: String
    let points: [RoutePoint]
    /// False when the source had no elevation data, so the route rides as dead flat.
    let hasElevation: Bool
    /// The group this route is listed under, e.g. a city. Nil for routes outside any group.
    var collection: String?
    /// Total climbing in metres, sampled every 10 m so GPS jitter doesn't inflate it.
    private(set) var elevationGain = 0.0

    var totalDistance: Double { points[points.count - 1].distance }

    /// - Parameter elevations: Per-coordinate elevation in metres; gaps are interpolated along the route.
    init(id: String, name: String, coordinates: [CLLocationCoordinate2D], elevations: [Double?]) throws {
        precondition(coordinates.count == elevations.count, "every coordinate needs an elevation slot")
        guard coordinates.count >= 2 else { throw RouteError.tooFewPoints(coordinates.count) }
        if let bad = coordinates.first(where: { !CLLocationCoordinate2DIsValid($0) }) {
            throw RouteError.invalidCoordinate(latitude: bad.latitude, longitude: bad.longitude)
        }

        var distances = [0.0]
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            distances.append(distances[distances.count - 1] + Geo.distance(from: a, to: b))
        }
        guard distances[distances.count - 1] > 0 else { throw RouteError.zeroLength }

        let filled = Self.fillGaps(in: elevations, distances: distances)
        self.id = id
        self.name = name
        self.hasElevation = filled != nil
        self.points = coordinates.indices.map { index in
            RoutePoint(
                latitude: coordinates[index].latitude,
                longitude: coordinates[index].longitude,
                elevation: filled?[index] ?? 0,
                distance: distances[index]
            )
        }
        elevationGain = stride(from: 0, through: totalDistance, by: 10)
            .map(elevation(at:))
            .adjacentPairs()
            .reduce(0) { $0 + max($1.1 - $1.0, 0) }
    }

    // MARK: Lookups by distance

    func elevation(at distance: Double) -> Double {
        let (a, b, fraction) = segment(at: distance)
        return a.elevation + (b.elevation - a.elevation) * fraction
    }

    /// Smoothed grade as a fraction (0.05 = 5%), clamped to ±25%.
    func grade(at distance: Double) -> Double {
        let half = Self.gradeWindowMeters / 2
        let start = clampDistance(distance - half)
        let end = clampDistance(distance + half)
        guard end > start else { return 0 }
        let grade = (elevation(at: end) - elevation(at: start)) / (end - start)
        return min(max(grade, -Self.maximumGrade), Self.maximumGrade)
    }

    func position(at distance: Double) -> RoutePosition {
        let (a, b, fraction) = segment(at: distance)
        // Bearing across a window around the rider rather than to the next vertex, so GPS-jagged
        // polylines don't make the heading flick back and forth.
        let behind = coordinate(at: distance - Self.headingWindowBehind)
        let ahead = coordinate(at: distance + Self.headingWindowAhead)
        let heading = Geo.distance(from: behind, to: ahead) > 0.5
            ? Geo.bearing(from: behind, to: ahead)
            : Geo.bearing(from: a.coordinate, to: b.coordinate)
        return RoutePosition(
            coordinate: Geo.interpolate(a.coordinate, b.coordinate, fraction: fraction),
            elevation: a.elevation + (b.elevation - a.elevation) * fraction,
            heading: heading
        )
    }

    static let headingWindowBehind = 15.0
    static let headingWindowAhead = 35.0

    private func coordinate(at distance: Double) -> CLLocationCoordinate2D {
        let (a, b, fraction) = segment(at: distance)
        return Geo.interpolate(a.coordinate, b.coordinate, fraction: fraction)
    }

    // MARK: Summary

    /// Evenly spaced (distance, elevation) samples for charting.
    func profile(sampleCount: Int = 300) -> [(distance: Double, elevation: Double)] {
        let count = max(sampleCount, 2)
        return (0..<count).map { index in
            let distance = totalDistance * Double(index) / Double(count - 1)
            return (distance, elevation(at: distance))
        }
    }

    // MARK: Private

    private func clampDistance(_ distance: Double) -> Double {
        min(max(distance, 0), totalDistance)
    }

    /// The segment containing `distance` and how far along it we are.
    private func segment(at distance: Double) -> (RoutePoint, RoutePoint, Double) {
        let d = clampDistance(distance)
        var low = 0
        var high = points.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if points[mid].distance <= d { low = mid } else { high = mid }
        }
        let a = points[low]
        let b = points[high]
        let length = b.distance - a.distance
        return (a, b, length > 0 ? (d - a.distance) / length : 0)
    }

    /// Linearly interpolates missing elevations by distance. Returns nil if none are present.
    private static func fillGaps(in elevations: [Double?], distances: [Double]) -> [Double]? {
        let known = elevations.indices.compactMap { index in elevations[index].map { (index, $0) } }
        guard let first = known.first, let last = known.last else { return nil }

        return elevations.indices.map { index in
            if let value = elevations[index] { return value }
            if index < first.0 { return first.1 }
            if index > last.0 { return last.1 }
            let before = known.last { $0.0 < index }!
            let after = known.first { $0.0 > index }!
            let span = distances[after.0] - distances[before.0]
            let fraction = span > 0 ? (distances[index] - distances[before.0]) / span : 0
            return before.1 + (after.1 - before.1) * fraction
        }
    }
}

private extension Sequence {
    func adjacentPairs() -> Zip2Sequence<[Element], ArraySlice<Element>> {
        let array = Array(self)
        return zip(array, array.dropFirst())
    }
}
