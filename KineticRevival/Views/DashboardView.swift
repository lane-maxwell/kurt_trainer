import SwiftUI

struct DashboardView: View {
    @Environment(BluetoothManager.self) private var bluetooth
    @AppStorage(UnitSystem.storageKey) private var units = UnitSystem.localeDefault
    @State private var isCalibrating = false

    private var trainer: TrainerController { bluetooth.trainer }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ConnectionBanner(state: bluetooth.state, controlState: trainer.controlState) {
                    bluetooth.cancelReconnect()
                }
                PowerHero(watts: trainer.latestData?.powerWatts)
                MetricsGrid(data: trainer.latestData, metrics: trainer.metrics, units: units)
                ControlPanel(isEnabled: isControllable)
                DeviceFooter(info: trainer.deviceInfo)
            }
            .padding()
        }
        .navigationTitle(connectedName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Disconnect", role: .destructive) {
                    Task { await bluetooth.disconnect() }
                }
                .disabled(bluetooth.state == .disconnecting)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("Calibrate (spin-down)", systemImage: "gauge.with.dots.needle.67percent") {
                        isCalibrating = true
                    }
                    .disabled(!isControllable || !trainer.supportsSpinDown)
                    Button("Reset ride totals", systemImage: "arrow.counterclockwise") {
                        trainer.resetRide()
                    }
                    Button("Forget this trainer", systemImage: "trash", role: .destructive) {
                        bluetooth.forgetTrainer()
                        Task { await bluetooth.disconnect() }
                    }
                }
            }
        }
        .sheet(isPresented: $isCalibrating) {
            CalibrationView(trainer: trainer)
        }
        .errorBanner(trainer.lastError ?? bluetooth.lastError) {
            trainer.dismissError()
            bluetooth.dismissError()
        }
    }

    private var isControllable: Bool {
        if case .connected = bluetooth.state { true } else { false }
    }

    private var connectedName: String {
        switch bluetooth.state {
        case let .connected(name), let .reconnecting(name): name
        default: "Trainer"
        }
    }
}

private struct ConnectionBanner: View {
    let state: ConnectionState
    let controlState: ControlState
    let cancelReconnect: () -> Void

    var body: some View {
        HStack {
            switch state {
            case .reconnecting:
                ProgressView()
                Text("Connection lost — reconnecting. Your target is restored if the trainer is back within a minute.")
                Spacer()
                Button("Cancel", action: cancelReconnect)
            case .disconnecting:
                ProgressView()
                Text("Releasing resistance and disconnecting…")
                Spacer()
            default:
                Circle()
                    .fill(controlColor)
                    .frame(width: 10, height: 10)
                Text(controlText)
                Spacer()
            }
        }
        .font(.subheadline)
        .padding(12)
        .background(.fill.tertiary, in: .rect(cornerRadius: 12))
    }

    private var controlColor: Color {
        switch controlState {
        case .granted: .green
        case .requesting: .yellow
        case .notConnected, .lost, .failed: .orange
        }
    }

    private var controlText: String {
        switch controlState {
        case .granted: "Connected · in control"
        case .requesting: "Requesting control…"
        case .notConnected: "Waiting for trainer…"
        case .lost: "Control lost — the next command will reclaim it"
        case let .failed(reason): "No control: \(reason)"
        }
    }
}

private struct PowerHero: View {
    let watts: Int?

    var body: some View {
        VStack(spacing: 0) {
            Text(watts.map(String.init) ?? "—")
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: watts)
            Text("watts")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct MetricsGrid: View {
    let data: IndoorBikeData?
    let metrics: RideMetrics
    let units: UnitSystem

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricTile(
                title: "Speed",
                value: data?.speedKph.map { units.speed(fromKph: $0).formatted(.number.precision(.fractionLength(1))) },
                unit: units.speedUnit
            )
            if data?.cadenceRpm != nil {
                MetricTile(
                    title: "Cadence",
                    value: data?.cadenceRpm.map { Int($0).formatted() },
                    unit: "rpm"
                )
            }
            MetricTile(title: "Moving time", value: metrics.movingTime.rideClock, unit: nil)
            MetricTile(
                title: "Distance",
                value: units.distance(fromMeters: metrics.distanceMeters).formatted(.number.precision(.fractionLength(2))),
                unit: units.distanceUnit
            )
            MetricTile(title: "Avg power", value: metrics.averagePowerWatts.map(String.init), unit: "W")
            MetricTile(title: "Max power", value: String(metrics.maximumPowerWatts), unit: "W")
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String?
    let unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value ?? "—")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.fill.tertiary, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

private struct DeviceFooter: View {
    let info: DeviceInfo

    var body: some View {
        let parts = [
            info.manufacturer,
            info.model.map { "model \($0)" },
            info.firmware.map { "firmware \($0)" },
        ].compactMap(\.self)

        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
