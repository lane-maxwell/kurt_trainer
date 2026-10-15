import SwiftUI

struct ControlPanel: View {
    enum Panel: String, CaseIterable, Identifiable {
        case resistance = "Resistance"
        case erg = "ERG"
        var id: Self { self }
    }

    @Environment(BluetoothManager.self) private var bluetooth
    @State private var panel: Panel = .resistance
    let isEnabled: Bool

    private var trainer: TrainerController { bluetooth.trainer }

    var body: some View {
        VStack(spacing: 16) {
            Picker("Mode", selection: $panel) {
                ForEach(Panel.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch panel {
            case .resistance:
                ResistanceControls(trainer: trainer)
            case .erg:
                ErgControls(trainer: trainer)
            }
        }
        .padding()
        .background(.fill.quaternary, in: .rect(cornerRadius: 16))
        .disabled(!isEnabled)
        .onAppear {
            if case .erg = trainer.displayedMode { panel = .erg }
        }
    }
}

private struct ResistanceControls: View {
    let trainer: TrainerController
    @State private var sliderValue = 0.0
    @State private var isDragging = false

    private var range: ClosedRange<Double> { trainer.limits.resistanceRange }

    var body: some View {
        VStack(spacing: 12) {
            TargetReadout(
                value: trainer.currentResistanceTarget.map { $0.formatted(.number.precision(.fractionLength(1))) },
                unit: "level",
                isPending: isPending
            )

            HStack {
                StepButton(label: "−5") { await trainer.adjustResistance(by: -5) }
                StepButton(label: "−1") { await trainer.adjustResistance(by: -1) }
                StepButton(label: "+1") { await trainer.adjustResistance(by: 1) }
                StepButton(label: "+5") { await trainer.adjustResistance(by: 5) }
            }

            Slider(value: $sliderValue, in: range, step: 1) {
                Text("Resistance level")
            } minimumValueLabel: {
                Text(range.lowerBound.formatted())
            } maximumValueLabel: {
                Text(range.upperBound.formatted())
            } onEditingChanged: { editing in
                isDragging = editing
                if !editing {
                    Task { await trainer.setResistance(sliderValue) }
                }
            }

            Button {
                Task { await trainer.releaseResistance() }
            } label: {
                Label("Release resistance", systemImage: "hand.raised")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .onChange(of: trainer.currentResistanceTarget, initial: true) { _, target in
            if !isDragging { sliderValue = target ?? range.lowerBound }
        }
    }

    private var isPending: Bool {
        if case .resistance = trainer.pendingMode { true } else { false }
    }
}

private struct ErgControls: View {
    let trainer: TrainerController

    var body: some View {
        VStack(spacing: 12) {
            if trainer.supportsErg {
                TargetReadout(
                    value: trainer.currentPowerTarget.map(String.init),
                    unit: "W target",
                    isPending: isPending
                )
                HStack {
                    StepButton(label: "−25") { await trainer.adjustTargetPower(by: -25) }
                    StepButton(label: "−5") { await trainer.adjustTargetPower(by: -5) }
                    StepButton(label: "+5") { await trainer.adjustTargetPower(by: 5) }
                    StepButton(label: "+25") { await trainer.adjustTargetPower(by: 25) }
                }
                Text("ERG holds your power at the target regardless of cadence. It hasn't been verified on the T-6400 yet, so start low and pedal steadily. Allowed range: \(trainer.limits.powerRange.lowerBound)–\(trainer.limits.powerRange.upperBound) W.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(TrainerError.powerTargetUnsupported.localizedDescription)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isPending: Bool {
        if case .erg = trainer.pendingMode { true } else { false }
    }
}

private struct TargetReadout: View {
    let value: String?
    let unit: String
    let isPending: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value ?? "—")
                .font(.system(size: 48, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .opacity(isPending ? 0.5 : 1)
            Text(unit)
                .foregroundStyle(.secondary)
            if isPending {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isPending ? "sending" : "confirmed")
    }
}

private struct StepButton: View {
    let label: String
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            Text(label)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
    }
}
