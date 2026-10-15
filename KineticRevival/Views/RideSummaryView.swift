import SwiftUI

struct RideSummaryView: View {
    let record: RideRecord?
    let onDone: () -> Void

    @Environment(RideStore.self) private var store
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Group {
                if let record {
                    RideStatsList(record: record)
                } else {
                    ContentUnavailableView("Nothing recorded", systemImage: "bicycle", description: Text("The ride ended before any distance was covered."))
                }
            }
            .navigationTitle("Ride complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard", role: .destructive, action: onDone)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(record == nil)
                }
            }
            .errorBanner(saveError) { saveError = nil }
        }
    }

    private func save() {
        guard let record else { return }
        do {
            try store.save(record)
            onDone()
        } catch {
            saveError = "Could not save the ride: \(error.localizedDescription)"
        }
    }
}

struct RideStatsList: View {
    let record: RideRecord
    @AppStorage(UnitSystem.storageKey) private var units = UnitSystem.localeDefault

    var body: some View {
        List {
            Section(record.routeName) {
                LabeledContent("Date", value: record.startedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Time", value: record.duration.rideClock)
                LabeledContent("Distance", value: units.formatDistance(record.distance))
                LabeledContent("Average speed", value: "\(units.speed(fromMetersPerSecond: record.averageSpeedMetersPerSecond).formatted(.number.precision(.fractionLength(1)))) \(units.speedUnit)")
                LabeledContent("Climbing", value: units.formatElevation(record.elevationGain))
            }
            Section("Power") {
                LabeledContent("Average", value: "\(record.averagePowerWatts) W")
                LabeledContent("Maximum", value: "\(record.maximumPowerWatts) W")
                LabeledContent("Work", value: "\(Int(record.workKilojoules.rounded())) kJ")
            }
        }
    }
}
