import SwiftUI

struct SettingsView: View {
    @AppStorage(UnitSystem.storageKey) private var units = UnitSystem.localeDefault
    @AppStorage(RiderSettings.riderWeightKey) private var riderWeightKg = RiderSettings.defaultRiderWeight
    @AppStorage(RiderSettings.bikeWeightKey) private var bikeWeightKg = RiderSettings.defaultBikeWeight
    @AppStorage(RiderSettings.difficultyKey) private var difficulty = RiderSettings.defaultDifficulty

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    weightStepper("Rider weight", kilograms: $riderWeightKg, range: RiderSettings.riderWeightRange)
                    weightStepper("Bike weight", kilograms: $bikeWeightKg, range: RiderSettings.bikeWeightRange)
                } header: {
                    Text("You")
                } footer: {
                    Text("Weight sets how fast you climb for a given power, just like on the road.")
                }

                Section {
                    VStack(alignment: .leading) {
                        LabeledContent("Trainer difficulty", value: difficulty.formatted(.percent.precision(.fractionLength(0))))
                        Slider(value: $difficulty, in: 0...1, step: 0.05)
                    }
                } header: {
                    Text("Route rides")
                } footer: {
                    Text("How much of the real gradient the trainer simulates. 50% is the usual default; your speed on the route always uses the full gradient.")
                }

                Section("Display") {
                    Picker("Units", selection: $units) {
                        Text("Metric").tag(UnitSystem.metric)
                        Text("Imperial").tag(UnitSystem.imperial)
                    }
                }

                Section {
                    Text("Kinetic Revival controls FTMS trainers directly over Bluetooth. Everything stays on this phone.")
                    Text("Built-in routes © OpenStreetMap contributors (ODbL), routed with FOSSGIS OSRM, with USGS 3DEP elevation.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Settings")
        }
    }

    private func weightStepper(_ title: String, kilograms: Binding<Double>, range: ClosedRange<Double>) -> some View {
        let displayed = Binding<Double>(
            get: { units.weight(fromKilograms: kilograms.wrappedValue).rounded() },
            set: { kilograms.wrappedValue = units.kilograms(fromWeight: $0).clamped(to: range) }
        )
        let displayRange = units.weight(fromKilograms: range.lowerBound).rounded()...units.weight(fromKilograms: range.upperBound).rounded()
        return Stepper(value: displayed, in: displayRange) {
            LabeledContent(title, value: "\(Int(displayed.wrappedValue)) \(units.weightUnit)")
        }
    }
}
