import SwiftUI

/// Guides the rider through an FTMS spin-down: speed up past the trainer's target, stop pedaling,
/// and let the flywheel coast while the trainer measures roller and tyre drag.
struct CalibrationView: View {
    let trainer: TrainerController

    @Environment(\.dismiss) private var dismiss
    @AppStorage(UnitSystem.storageKey) private var units = UnitSystem.localeDefault

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    content
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Spin-down calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(trainer.spinDownState.isInProgress ? "Cancel" : "Done") {
                        if trainer.spinDownState.isInProgress { trainer.cancelSpinDown() }
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(trainer.spinDownState.isInProgress)
        .onDisappear {
            if !trainer.spinDownState.isInProgress { trainer.cancelSpinDown() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch trainer.spinDownState {
        case .idle:
            Instructions(onStart: start)
        case .starting:
            ProgressView("Asking the trainer to start…")
        case let .speedUp(target):
            SpeedUpView(target: target, currentKph: trainer.latestData?.speedKph ?? 0, units: units)
        case .coasting:
            StatusCard(
                symbol: "hand.raised.fill",
                tint: .orange,
                title: "Stop pedaling!",
                message: "Let the wheel coast to a stop on its own. Don't touch the brakes or the pedals."
            )
        case .succeeded:
            StatusCard(
                symbol: "checkmark.circle.fill",
                tint: .green,
                title: "Calibrated",
                message: "Power and resistance now account for your current roller tension and tyre. Recalibrate after changing tension, tyre pressure, or once you're warmed up."
            )
        case let .failed(reason):
            StatusCard(symbol: "exclamationmark.triangle.fill", tint: .red, title: "Calibration didn't finish", message: reason)
            Button("Try again", action: start)
                .buttonStyle(.borderedProminent)
        }
    }

    private func start() {
        Task { await trainer.startSpinDown() }
    }
}

private struct Instructions: View {
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How hard the trainer brakes, and the power it reports, depend on how firmly the roller presses on your tyre. A spin-down measures that drag so the numbers stay honest.")

            VStack(alignment: .leading, spacing: 12) {
                Step(number: 1, text: "Mount the bike and pump the rear tyre to your usual pressure.")
                Step(number: 2, text: "Set the roller tension the same way every time, e.g. a fixed number of knob turns after the roller first touches the tyre.")
                Step(number: 3, text: "Warm up for about 10 minutes. A cold tyre and fluid read differently.")
                Step(number: 4, text: "Tap Start, pedal up past the target speed, then stop pedaling completely when told.")
            }

            Button(action: onStart) {
                Label("Start calibration", systemImage: "gauge.with.dots.needle.67percent")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

private struct Step: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(.orange.opacity(0.2), in: .circle)
            Text(text)
        }
    }
}

private struct SpeedUpView: View {
    let target: SpinDownTarget?
    let currentKph: Double
    let units: UnitSystem

    var body: some View {
        VStack(spacing: 16) {
            Text(isAboveTarget ? "Hold it there…" : "Pedal up to speed")
                .font(.title2.weight(.semibold))

            Text(units.speed(fromKph: currentKph).formatted(.number.precision(.fractionLength(1))))
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isAboveTarget ? .green : .primary)
                .contentTransition(.numericText())
                .animation(.snappy, value: currentKph)
            Text(units.speedUnit)
                .foregroundStyle(.secondary)

            if let target {
                ProgressView(value: min(currentKph / target.highKph, 1))
                    .tint(isAboveTarget ? .green : .orange)
                Text("Get above \(format(target.highKph)), then wait for the signal to stop pedaling.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                Text("Pedal briskly (around 20 mph / 32 km/h) until the app tells you to stop.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isAboveTarget: Bool {
        target.map { currentKph >= $0.highKph } ?? false
    }

    private func format(_ kph: Double) -> String {
        "\(units.speed(fromKph: kph).formatted(.number.precision(.fractionLength(1)))) \(units.speedUnit)"
    }
}

private struct StatusCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 72))
                .foregroundStyle(tint)
            Text(title)
                .font(.largeTitle.weight(.bold))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 32)
    }
}
