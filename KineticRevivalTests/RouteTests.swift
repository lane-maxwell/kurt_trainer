import CoreLocation
import Foundation
import Testing
@testable import KineticRevival

/// A straight route heading north along a meridian, where 1° of latitude ≈ 111.2 km.
func straightRoute(lengthMeters: Double = 1000, pointCount: Int = 11, elevation: (Double) -> Double?) throws -> Route {
    let degreesPerMeter = 1 / (Geo.earthRadiusMeters * .pi / 180)
    let distances = (0..<pointCount).map { lengthMeters * Double($0) / Double(pointCount - 1) }
    return try Route(
        id: "test",
        name: "Test",
        coordinates: distances.map { CLLocationCoordinate2D(latitude: 45 + $0 * degreesPerMeter, longitude: 7) },
        elevations: distances.map(elevation)
    )
}

struct RouteTests {
    @Test func measuresDistanceAlongTheRoute() throws {
        let route = try straightRoute { _ in 100 }
        #expect(abs(route.totalDistance - 1000) < 0.01)
    }

    @Test func computesSteadyGrade() throws {
        let route = try straightRoute { $0 * 0.05 }

        #expect(abs(route.grade(at: 500) - 0.05) < 1e-6)
        #expect(abs(route.grade(at: 0) - 0.05) < 1e-6)
        #expect(abs(route.grade(at: 1000) - 0.05) < 1e-6)
    }

    @Test func clampsImplausibleGrades() throws {
        let route = try straightRoute(lengthMeters: 100) { $0 }
        #expect(route.grade(at: 50) == Route.maximumGrade)
    }

    @Test func interpolatesElevationBetweenPoints() throws {
        let route = try straightRoute { $0 * 0.1 }
        #expect(abs(route.elevation(at: 250) - 25) < 1e-6)
    }

    @Test func clampsLookupsOutsideTheRoute() throws {
        let route = try straightRoute { $0 * 0.1 }

        #expect(route.elevation(at: -50) == 0)
        #expect(abs(route.elevation(at: 5000) - 100) < 1e-6)
    }

    @Test func headsInTheDirectionOfTravel() throws {
        let route = try straightRoute { _ in 0 }
        let position = route.position(at: 500)

        #expect(position.heading < 0.01 || position.heading > 359.99)
        #expect(position.coordinate.latitude > 45)
    }

    @Test(arguments: [
        (350.0, 10.0, 0.5, 0.0),
        (10.0, 350.0, 0.5, 0.0),
        (90.0, 180.0, 0.5, 135.0),
        (0.0, 170.0, 0.25, 42.5),
        (45.0, 45.0, 0.3, 45.0),
    ])
    func blendsHeadingsTheShortWayRound(from: Double, to: Double, fraction: Double, expected: Double) {
        let result = Geo.blendHeading(from, toward: to, fraction: fraction)
        #expect(abs(result - expected) < 1e-9 || abs(result - expected - 360) < 1e-9)
    }

    @Test func headingIgnoresSmallZigZags() throws {
        let degreesPerMeter = 1 / (Geo.earthRadiusMeters * .pi / 180)
        // Heading north with 1 m sideways wobble every 5 m, like a noisy GPS trace.
        let coordinates = (0...200).map { index in
            CLLocationCoordinate2D(
                latitude: 45 + Double(index) * 5 * degreesPerMeter,
                longitude: 7 + (index.isMultiple(of: 2) ? 0 : 1 * degreesPerMeter)
            )
        }
        let route = try Route(id: "zz", name: "zz", coordinates: coordinates, elevations: coordinates.map { _ in nil })

        let headings = stride(from: 100.0, through: 900, by: 7).map { route.position(at: $0).heading }
        #expect(headings.allSatisfy { $0 < 5 || $0 > 355 })
    }

    @Test func sumsClimbingButNotDescending() throws {
        let route = try straightRoute(lengthMeters: 2000, pointCount: 3) { distance in
            distance <= 1000 ? distance * 0.05 : 50 - (distance - 1000) * 0.05
        }
        #expect(abs(route.elevationGain - 50) < 0.5)
    }

    @Test func fillsMissingElevationsByDistance() throws {
        let route = try straightRoute(pointCount: 3) { distance in
            distance == 500 ? nil : distance * 0.1
        }

        #expect(route.hasElevation)
        #expect(abs(route.points[1].elevation - 50) < 1e-6)
    }

    @Test func ridesFlatWithoutElevationData() throws {
        let route = try straightRoute { _ in nil }

        #expect(!route.hasElevation)
        #expect(route.grade(at: 500) == 0)
    }

    @Test func rejectsDegenerateRoutes() {
        let point = CLLocationCoordinate2D(latitude: 45, longitude: 7)

        #expect(throws: RouteError.tooFewPoints(1)) {
            try Route(id: "x", name: "x", coordinates: [point], elevations: [nil])
        }
        #expect(throws: RouteError.zeroLength) {
            try Route(id: "x", name: "x", coordinates: [point, point], elevations: [nil, nil])
        }
        #expect(throws: RouteError.self) {
            try Route(id: "x", name: "x", coordinates: [point, CLLocationCoordinate2D(latitude: 95, longitude: 7)], elevations: [nil, nil])
        }
    }

    @Test func profileSpansTheWholeRoute() throws {
        let route = try straightRoute { $0 * 0.05 }
        let profile = route.profile(sampleCount: 5)

        #expect(profile.count == 5)
        #expect(profile.first?.distance == 0)
        #expect(abs((profile.last?.distance ?? 0) - route.totalDistance) < 1e-9)
    }

    @Test(arguments: [(2.0, Terrain.flat), (8.0, .rolling), (15.0, .hilly), (40.0, .mountain)])
    func classifiesTerrainByClimbingRate(rate: Double, expected: Terrain) {
        #expect(Terrain(climbingMetersPerKilometer: rate) == expected)
    }

    @Test func demoRouteIsRideable() {
        let route = DemoRoute.make()

        #expect(abs(route.totalDistance - 10_000) < 50)
        #expect(route.elevationGain > 150)
        #expect(route.grade(at: 3000) > 0.03)
    }
}

struct GPXParserTests {
    private func parse(_ xml: String) throws -> Route {
        try GPXParser.parse(Data(xml.utf8), id: "file.gpx", fallbackName: "Fallback")
    }

    @Test func parsesTrackWithNameAndElevation() throws {
        let route = try parse("""
            <?xml version="1.0"?>
            <gpx version="1.1" creator="test" xmlns="http://www.topografix.com/GPX/1/1">
              <metadata><name>Morning Climb</name></metadata>
              <trk><name>Track name</name><trkseg>
                <trkpt lat="45.0" lon="7.0"><ele>100</ele><time>2024-01-01T00:00:00Z</time></trkpt>
                <trkpt lat="45.001" lon="7.0"><ele>105.5</ele></trkpt>
              </trkseg><trkseg>
                <trkpt lat="45.002" lon="7.0"><ele>110</ele></trkpt>
              </trkseg></trk>
            </gpx>
            """)

        #expect(route.name == "Morning Climb")
        #expect(route.points.count == 3)
        #expect(route.points[1].elevation == 105.5)
        #expect(route.hasElevation)
    }

    @Test func readsNamesWrappedInCDATA() throws {
        let route = try parse("""
            <gpx><metadata><name><![CDATA[River & Bluff Trail]]></name></metadata><trk><trkseg>
              <trkpt lat="45.0" lon="7.0"><ele>100</ele></trkpt>
              <trkpt lat="45.001" lon="7.0"><ele>101</ele></trkpt>
            </trkseg></trk></gpx>
            """)

        #expect(route.name == "River & Bluff Trail")
    }

    @Test func fallsBackToRoutePoints() throws {
        let route = try parse("""
            <gpx><rte>
              <rtept lat="45.0" lon="7.0"/>
              <rtept lat="45.01" lon="7.0"/>
            </rte></gpx>
            """)

        #expect(route.points.count == 2)
        #expect(route.name == "Fallback")
        #expect(!route.hasElevation)
    }

    @Test func ignoresElevationInsideExtensions() throws {
        let route = try parse("""
            <gpx><trk><trkseg>
              <trkpt lat="45.0" lon="7.0"><extensions><x:ele>999</x:ele></extensions></trkpt>
              <trkpt lat="45.01" lon="7.0"><ele>10</ele></trkpt>
            </trkseg></trk></gpx>
            """)

        #expect(route.points[0].elevation == 10)
    }

    @Test func handlesPrefixedElements() throws {
        let route = try parse("""
            <g:gpx xmlns:g="http://www.topografix.com/GPX/1/1"><g:trk><g:trkseg>
              <g:trkpt lat="45.0" lon="7.0"><g:ele>1</g:ele></g:trkpt>
              <g:trkpt lat="45.01" lon="7.0"><g:ele>2</g:ele></g:trkpt>
            </g:trkseg></g:trk></g:gpx>
            """)

        #expect(route.points.map(\.elevation) == [1, 2])
    }

    @Test func rejectsFilesWithoutPoints() {
        #expect(throws: GPXError.self) { try parse("<gpx><metadata/></gpx>") }
    }

    @Test func rejectsMalformedXML() {
        #expect(throws: GPXError.self) { try parse("<gpx><trk>") }
    }

    @Test func rejectsPointsWithoutCoordinates() {
        #expect(throws: GPXError.self) { try parse(#"<gpx><trk><trkseg><trkpt lat="45"/></trkseg></trk></gpx>"#) }
    }
}
