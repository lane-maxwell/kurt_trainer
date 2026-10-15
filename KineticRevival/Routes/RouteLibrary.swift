import Foundation
import Observation
import os

/// The demo route, GPX routes bundled with the app, and routes the user imported (stored in
/// Documents/Routes so they're also visible in the Files app).
@MainActor
@Observable
final class RouteLibrary {
    private static let logger = Logger(subsystem: "com.kineticrevival.trainer", category: "Routes")

    struct Section: Identifiable {
        let title: String
        let routes: [Route]
        var id: String { title }
    }

    static let myRoutesTitle = "My Routes"
    static let gettingStartedTitle = "Getting Started"
    /// Optional JSON array in the built-in folder giving the collection order (home city first).
    static let orderFileName = "order.json"

    /// Imported routes first, then built-in collections in `order.json` order, then the demo.
    private(set) var sections: [Section] = []
    private(set) var lastError: String?

    var routes: [Route] { sections.flatMap(\.routes) }

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let builtInDirectory: URL?
    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private var builtInIDs: Set<Route.ID> = [DemoRoute.id]

    static let builtInIDPrefix = "builtin:"

    init(
        directory: URL? = nil,
        builtInDirectory: URL? = Bundle.main.url(forResource: "Routes", withExtension: nil),
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.directory = directory ?? URL.documentsDirectory.appending(path: "Routes", directoryHint: .isDirectory)
        self.builtInDirectory = builtInDirectory
        reload()
    }

    func isBuiltIn(_ route: Route) -> Bool {
        builtInIDs.contains(route.id)
    }

    func reload() {
        let builtIn = loadBuiltInRoutes()
        builtInIDs = Set([DemoRoute.id] + builtIn.map(\.id))

        var imported: [Route] = []
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            imported = try gpxFiles(in: directory).compactMap { loadRoute(at: $0, id: $0.lastPathComponent) }
        } catch {
            Self.logger.error("Could not list routes: \(error.localizedDescription, privacy: .public)")
            lastError = "Could not load your routes: \(error.localizedDescription)"
        }

        var result: [Section] = []
        if !imported.isEmpty {
            result.append(Section(title: Self.myRoutesTitle, routes: sortedByName(imported)))
        }
        let grouped = Dictionary(grouping: builtIn) { $0.collection ?? "Featured" }
        result += orderedCollectionTitles(Array(grouped.keys)).map { title in
            Section(title: title, routes: sortedByName(grouped[title] ?? []))
        }
        result.append(Section(title: Self.gettingStartedTitle, routes: [DemoRoute.make()]))
        sections = result
    }

    /// Validates the GPX, then copies it into the library. Returns the imported route.
    @discardableResult
    func importGPX(from source: URL) throws -> Route {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: source)
        let destination = uniqueDestination(for: source.deletingPathExtension().lastPathComponent)
        let route = try GPXParser.parse(
            data,
            id: destination.lastPathComponent,
            fallbackName: source.deletingPathExtension().lastPathComponent
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        Self.logger.info("Imported route \(route.name, privacy: .public) (\(Int(route.totalDistance)) m)")
        reload()
        return route
    }

    func delete(_ route: Route) throws {
        guard !isBuiltIn(route) else { return }
        try fileManager.removeItem(at: directory.appending(path: route.id))
        reload()
    }

    func dismissError() {
        lastError = nil
    }

    /// GPX files at the top level are ungrouped; each subfolder is a collection named after it.
    private func loadBuiltInRoutes() -> [Route] {
        guard let builtInDirectory else { return [] }
        do {
            let entries = try fileManager.contentsOfDirectory(at: builtInDirectory, includingPropertiesForKeys: [.isDirectoryKey])
            let folders = entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            let ungrouped = try gpxFiles(in: builtInDirectory).compactMap {
                loadRoute(at: $0, id: Self.builtInIDPrefix + $0.lastPathComponent)
            }
            let grouped = try folders.flatMap { folder in
                try gpxFiles(in: folder).compactMap { file -> Route? in
                    var route = loadRoute(at: file, id: "\(Self.builtInIDPrefix)\(folder.lastPathComponent)/\(file.lastPathComponent)")
                    route?.collection = folder.lastPathComponent
                    return route
                }
            }
            return ungrouped + grouped
        } catch {
            Self.logger.error("Could not list built-in routes: \(error.localizedDescription, privacy: .public)")
            lastError = "Some built-in routes couldn't be loaded."
            return []
        }
    }

    private func orderedCollectionTitles(_ titles: [String]) -> [String] {
        let preferred = builtInDirectory
            .flatMap { try? Data(contentsOf: $0.appending(path: Self.orderFileName)) }
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        let known = preferred.filter(titles.contains)
        let rest = titles.filter { !preferred.contains($0) }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return known + rest
    }

    private func gpxFiles(in directory: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "gpx" }
    }

    private func sortedByName(_ routes: [Route]) -> [Route] {
        routes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func loadRoute(at url: URL, id: Route.ID) -> Route? {
        do {
            return try GPXParser.parse(
                Data(contentsOf: url),
                id: id,
                fallbackName: url.deletingPathExtension().lastPathComponent
            )
        } catch {
            Self.logger.error("Skipping unreadable route \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            lastError = "\(url.lastPathComponent) couldn't be loaded: \(error.localizedDescription)"
            return nil
        }
    }

    private func uniqueDestination(for baseName: String) -> URL {
        let safeName = baseName.isEmpty ? "Route" : baseName
        var candidate = directory.appending(path: "\(safeName).gpx")
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path()) {
            candidate = directory.appending(path: "\(safeName) \(suffix).gpx")
            suffix += 1
        }
        return candidate
    }
}
