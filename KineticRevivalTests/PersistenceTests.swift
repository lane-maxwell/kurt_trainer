import Foundation
import Testing
@testable import KineticRevival

@MainActor
struct RouteLibraryTests {
    private let directory = URL.temporaryDirectory.appending(path: "RouteLibraryTests-\(UUID().uuidString)")

    private func writeSource(_ name: String, _ contents: String) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString)-src").appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private let validGPX = """
        <gpx><trk><name>Hill</name><trkseg>
          <trkpt lat="45.0" lon="7.0"><ele>1</ele></trkpt>
          <trkpt lat="45.01" lon="7.0"><ele>50</ele></trkpt>
        </trkseg></trk></gpx>
        """

    @Test func alwaysOffersTheDemoRoute() {
        let library = RouteLibrary(directory: directory, builtInDirectory: nil)

        #expect(library.routes.map(\.id) == [DemoRoute.id])
        #expect(library.sections.map(\.title) == [RouteLibrary.gettingStartedTitle])
    }

    @Test func importsAndPersistsGPX() throws {
        let library = RouteLibrary(directory: directory, builtInDirectory: nil)
        let source = try writeSource("hill.gpx", validGPX)

        let route = try library.importGPX(from: source)

        #expect(route.name == "Hill")
        #expect(library.routes.map(\.name).contains("Hill"))
        #expect(RouteLibrary(directory: directory, builtInDirectory: nil).routes.count == 2)
    }

    @Test func keepsBothCopiesWhenNamesCollide() throws {
        let library = RouteLibrary(directory: directory, builtInDirectory: nil)
        try library.importGPX(from: try writeSource("hill.gpx", validGPX))
        try library.importGPX(from: try writeSource("hill.gpx", validGPX))

        #expect(library.routes.count == 3)
        #expect(Set(library.routes.map(\.id)).count == 3)
    }

    @Test func rejectsInvalidGPXWithoutStoringIt() throws {
        let library = RouteLibrary(directory: directory, builtInDirectory: nil)

        #expect(throws: GPXError.self) {
            try library.importGPX(from: try writeSource("bad.gpx", "<gpx></gpx>"))
        }
        #expect(library.routes.count == 1)
    }

    @Test func deletesImportedRoutesButNotTheDemo() throws {
        let library = RouteLibrary(directory: directory, builtInDirectory: nil)
        let route = try library.importGPX(from: try writeSource("hill.gpx", validGPX))

        try library.delete(route)
        try library.delete(DemoRoute.make())

        #expect(library.routes.map(\.id) == [DemoRoute.id])
    }

    @Test func loadsBuiltInRoutesThatCannotBeDeleted() throws {
        let builtIn = URL.temporaryDirectory.appending(path: "BuiltIn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: builtIn, withIntermediateDirectories: true)
        try validGPX.write(to: builtIn.appending(path: "hill.gpx"), atomically: true, encoding: .utf8)

        let library = RouteLibrary(directory: directory, builtInDirectory: builtIn)
        let route = try #require(library.routes.first { $0.name == "Hill" })
        try library.delete(route)

        #expect(route.id == RouteLibrary.builtInIDPrefix + "hill.gpx")
        #expect(library.isBuiltIn(route))
        #expect(library.routes.map(\.id) == [route.id, DemoRoute.id])
    }

    @Test func groupsRoutesIntoOrderedSections() throws {
        let builtIn = URL.temporaryDirectory.appending(path: "BuiltIn-\(UUID().uuidString)")
        for folder in ["Boston, MA", "Austin, TX", "St. Louis, MO"] {
            let url = builtIn.appending(path: folder)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try validGPX.replacingOccurrences(of: "Hill", with: "\(folder) B").write(to: url.appending(path: "b.gpx"), atomically: true, encoding: .utf8)
            try validGPX.replacingOccurrences(of: "Hill", with: "\(folder) A").write(to: url.appending(path: "a.gpx"), atomically: true, encoding: .utf8)
        }
        try #"["St. Louis, MO", "Missing City"]"#.write(to: builtIn.appending(path: RouteLibrary.orderFileName), atomically: true, encoding: .utf8)
        let library = RouteLibrary(directory: directory, builtInDirectory: builtIn)

        try library.importGPX(from: try writeSource("mine.gpx", validGPX.replacingOccurrences(of: "Hill", with: "Mine")))

        #expect(library.sections.map(\.title) == [
            RouteLibrary.myRoutesTitle, "St. Louis, MO", "Austin, TX", "Boston, MA", RouteLibrary.gettingStartedTitle,
        ])
        #expect(library.sections[1].routes.map(\.name) == ["St. Louis, MO A", "St. Louis, MO B"])
        #expect(library.sections[1].routes.allSatisfy { $0.collection == "St. Louis, MO" && library.isBuiltIn($0) })
        #expect(!library.isBuiltIn(library.sections[0].routes[0]))
    }

    @Test func shipsTheBundledTrails() {
        let library = RouteLibrary(directory: directory)
        let homeNames = Set(library.sections.first { $0.title == "St. Louis, MO" }?.routes.map(\.name) ?? [])

        #expect(library.sections.first?.title == "St. Louis, MO")
        #expect(homeNames.isSuperset(of: ["Grant's Trail", "Al Foster Trail", "Katy Trail - St. Charles to Defiance"]))
        #expect(library.routes.allSatisfy { $0.hasElevation })
        #expect(library.lastError == nil)
    }

    /// Built-in routes must be redistributable: built from OpenStreetMap and USGS data, not copied
    /// from services whose terms forbid it.
    @Test func bundledRoutesComeFromOpenData() throws {
        let folder = try #require(Bundle.main.url(forResource: "Routes", withExtension: nil))
        let files = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "gpx" }

        #expect(files.count >= 25)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8).lowercased()
            #expect(!text.contains("alltrails") && !text.contains("ridewithgps"), "\(file.lastPathComponent) is third-party data")
            #expect(text.contains("openstreetmap"), "\(file.lastPathComponent) is missing its OpenStreetMap attribution")
        }
    }

    /// Guards against bad elevation data (e.g. a river under a bridge) turning flat trails into walls.
    /// Climbs like Teton Pass genuinely have steep pitches, so only gentle routes are checked.
    @Test func gentleBundledTrailsHaveNoWalls() {
        let library = RouteLibrary(directory: directory)
        let gentle = library.routes.filter {
            library.isBuiltIn($0) && $0.id != DemoRoute.id && [.flat, .rolling].contains($0.terrain)
        }

        #expect(!gentle.isEmpty)
        for route in gentle {
            let grades = stride(from: 0, through: route.totalDistance, by: 10).map { abs(route.grade(at: $0)) }
            let steep = grades.filter { $0 > 0.12 }.count
            #expect(Double(steep) / Double(grades.count) < 0.02, "\(route.name) has too many >12% stretches")
        }
    }

    @Test func skipsCorruptFilesAndReportsThem() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "not xml".write(to: directory.appending(path: "broken.gpx"), atomically: true, encoding: .utf8)

        let library = RouteLibrary(directory: directory, builtInDirectory: nil)

        #expect(library.routes.count == 1)
        #expect(library.lastError?.contains("broken.gpx") == true)
    }
}

@MainActor
struct RideStoreTests {
    private let directory = URL.temporaryDirectory.appending(path: "RideStoreTests-\(UUID().uuidString)")

    private func record(startedAt: Date) -> RideRecord {
        let sample = RideSample(
            timestamp: startedAt, elapsed: 0, distance: 0, speedMetersPerSecond: 0,
            powerWatts: 0, cadenceRpm: nil, latitude: 45, longitude: 7, elevation: 0
        )
        return RideRecord(id: UUID(), routeName: "A/B: test", startedAt: startedAt, samples: [sample])
    }

    @Test func savesAndReloadsNewestFirst() throws {
        let store = RideStore(directory: directory)
        let older = record(startedAt: Date(timeIntervalSince1970: 1000))
        let newer = record(startedAt: Date(timeIntervalSince1970: 2000))

        try store.save(older)
        try store.save(newer)

        #expect(RideStore(directory: directory).rides.map(\.id) == [newer.id, older.id])
    }

    @Test func deletesRides() throws {
        let store = RideStore(directory: directory)
        let ride = record(startedAt: .now)
        try store.save(ride)

        try store.delete(ride)

        #expect(store.rides.isEmpty)
    }

    @Test func exportsTCXWithSafeFileName() throws {
        let store = RideStore(directory: directory)

        let url = try store.exportTCX(record(startedAt: Date(timeIntervalSince1970: 0)))

        #expect(url.lastPathComponent == "1970-01-01 A-B- test.tcx")
        #expect(try String(contentsOf: url, encoding: .utf8).contains("<TrainingCenterDatabase"))
    }
}
