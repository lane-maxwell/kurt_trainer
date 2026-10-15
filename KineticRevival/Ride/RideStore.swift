import Foundation
import Observation
import os

/// Saved rides as JSON in Documents/Rides, newest first.
@MainActor
@Observable
final class RideStore {
    private static let logger = Logger(subsystem: "com.kineticrevival.trainer", category: "RideStore")

    private(set) var rides: [RideRecord] = []
    private(set) var lastError: String?

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let fileManager: FileManager

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = directory ?? URL.documentsDirectory.appending(path: "Rides", directoryHint: .isDirectory)
        reload()
    }

    func reload() {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            rides = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .compactMap(load(at:))
                .sorted { $0.startedAt > $1.startedAt }
        } catch {
            Self.logger.error("Could not list rides: \(error.localizedDescription, privacy: .public)")
            lastError = "Could not load ride history: \(error.localizedDescription)"
        }
    }

    func save(_ record: RideRecord) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(record).write(to: fileURL(for: record), options: .atomic)
        reload()
    }

    func delete(_ record: RideRecord) throws {
        try fileManager.removeItem(at: fileURL(for: record))
        reload()
    }

    /// Writes a TCX copy to the temporary directory for sharing.
    func exportTCX(_ record: RideRecord) throws -> URL {
        let day = record.startedAt.formatted(.iso8601.year().month().day())
        let name = "\(day) \(record.routeName)"
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: "-")
        let url = URL.temporaryDirectory.appending(path: "\(name).tcx")
        try TCXExporter.export(record).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func dismissError() {
        lastError = nil
    }

    private func fileURL(for record: RideRecord) -> URL {
        directory.appending(path: "\(record.id.uuidString).json")
    }

    private func load(at url: URL) -> RideRecord? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(RideRecord.self, from: Data(contentsOf: url))
        } catch {
            Self.logger.error("Skipping unreadable ride \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            lastError = "A saved ride couldn't be read and was skipped."
            return nil
        }
    }
}
