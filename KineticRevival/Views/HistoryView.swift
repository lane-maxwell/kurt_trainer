import SwiftUI

struct HistoryView: View {
    @Environment(RideStore.self) private var store
    @AppStorage(UnitSystem.storageKey) private var units = UnitSystem.localeDefault
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            Group {
                if store.rides.isEmpty {
                    ContentUnavailableView("No rides yet", systemImage: "clock", description: Text("Finished route rides you save show up here."))
                } else {
                    List {
                        ForEach(store.rides) { ride in
                            NavigationLink(value: ride.id) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(ride.routeName).font(.headline)
                                    Text("\(ride.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(units.formatDistance(ride.distance)) · \(ride.duration.rideClock) · \(ride.averagePowerWatts) W avg")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: RideRecord.ID.self) { id in
                if let ride = store.rides.first(where: { $0.id == id }) {
                    RideDetailView(record: ride)
                }
            }
            .errorBanner(deleteError ?? store.lastError) {
                deleteError = nil
                store.dismissError()
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        do {
            for ride in offsets.map({ store.rides[$0] }) {
                try store.delete(ride)
            }
        } catch {
            deleteError = "Could not delete ride: \(error.localizedDescription)"
        }
    }
}

private struct RideDetailView: View {
    let record: RideRecord

    @Environment(RideStore.self) private var store
    @State private var exportURL: URL?
    @State private var exportError: String?

    var body: some View {
        RideStatsList(record: record)
            .navigationTitle(record.routeName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let exportURL {
                    ShareLink("Export TCX", item: exportURL)
                }
            }
            .task {
                do {
                    exportURL = try store.exportTCX(record)
                } catch {
                    exportError = "Could not prepare the TCX export: \(error.localizedDescription)"
                }
            }
            .errorBanner(exportError) { exportError = nil }
    }
}
