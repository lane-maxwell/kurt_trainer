import SwiftUI
import UniformTypeIdentifiers

struct RoutesView: View {
    @Environment(RouteLibrary.self) private var library
    @AppStorage(UnitSystem.storageKey) private var units = UnitSystem.localeDefault
    @State private var isImporting = false
    @State private var importError: String?
    @State private var searchText = ""

    private static let gpxTypes: [UTType] = [UTType(filenameExtension: "gpx"), .xml].compactMap(\.self)

    var body: some View {
        NavigationStack {
            List {
                if searchText.isEmpty {
                    TrainerStatusRow()
                }

                ForEach(visibleSections) { section in
                    Section {
                        ForEach(section.routes) { route in
                            NavigationLink(value: route.id) {
                                RouteRow(route: route, units: units)
                            }
                            .deleteDisabled(library.isBuiltIn(route))
                        }
                        .onDelete { offsets in delete(offsets.map { section.routes[$0] }) }
                    } header: {
                        Text(section.title)
                    }
                }

                if searchText.isEmpty {
                    Section {
                        Button("Import GPX", systemImage: "square.and.arrow.down") { isImporting = true }
                    } footer: {
                        Text("Import GPX files exported from Strava, Komoot, RideWithGPS or Garmin. You can also copy them into the app's Routes folder with Finder or the Files app.")
                    }
                } else if visibleSections.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .navigationTitle("Ride a Route")
            .searchable(text: $searchText, prompt: "Trail, city or terrain")
            .navigationDestination(for: Route.ID.self) { id in
                if let route = library.routes.first(where: { $0.id == id }) {
                    RouteDetailView(route: route)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Import GPX", systemImage: "square.and.arrow.down") { isImporting = true }
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: Self.gpxTypes, allowsMultipleSelection: true) { result in
                importRoutes(result)
            }
            .refreshable { library.reload() }
            .errorBanner(importError ?? library.lastError) {
                importError = nil
                library.dismissError()
            }
        }
    }

    private func importRoutes(_ result: Result<[URL], Error>) {
        do {
            for url in try result.get() {
                try library.importGPX(from: url)
            }
        } catch {
            importError = error.localizedDescription
        }
    }

    private var visibleSections: [RouteLibrary.Section] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return library.sections }
        return library.sections.compactMap { section in
            let matches = section.title.localizedCaseInsensitiveContains(query)
                ? section.routes
                : section.routes.filter {
                    $0.name.localizedCaseInsensitiveContains(query)
                        || $0.terrain.rawValue.localizedCaseInsensitiveContains(query)
                }
            return matches.isEmpty ? nil : RouteLibrary.Section(title: section.title, routes: matches)
        }
    }

    private func delete(_ routes: [Route]) {
        do {
            for route in routes {
                try library.delete(route)
            }
        } catch {
            importError = "Could not delete route: \(error.localizedDescription)"
        }
    }
}

private struct RouteRow: View {
    let route: Route
    let units: UnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(route.name)
                    .font(.headline)
                Spacer()
                TerrainBadge(terrain: route.terrain)
            }
            HStack(spacing: 12) {
                Label(units.formatDistance(route.totalDistance), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                Label(units.formatElevation(route.elevationGain), systemImage: "mountain.2")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ElevationProfileView(route: route, showsAxes: false)
                .frame(height: 36)
        }
        .padding(.vertical, 4)
    }
}

struct TerrainBadge: View {
    let terrain: Terrain

    var body: some View {
        Text(terrain.rawValue)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(terrain.color.opacity(0.2), in: .capsule)
            .foregroundStyle(terrain.color)
    }
}

struct TrainerStatusRow: View {
    @Environment(BluetoothManager.self) private var bluetooth

    var body: some View {
        Section {
            switch bluetooth.state {
            case let .connected(name):
                Label("\(name) connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case let .reconnecting(name):
                Label("Reconnecting to \(name)…", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
            default:
                Label("No trainer connected. Connect one in the Trainer tab, or preview a route with a simulated rider.", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
