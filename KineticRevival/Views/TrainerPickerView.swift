import SwiftUI

struct TrainerPickerView: View {
    @Environment(BluetoothManager.self) private var bluetooth

    var body: some View {
        List {
            statusSection

            if !bluetooth.discovered.isEmpty {
                Section("Trainers nearby") {
                    ForEach(bluetooth.discovered) { trainer in
                        Button {
                            bluetooth.connect(to: trainer)
                        } label: {
                            TrainerRow(trainer: trainer)
                        }
                        .disabled(isConnecting)
                    }
                }
            }

            Section {
                Text("Kinetic Revival talks to your trainer directly over Bluetooth FTMS. No account, no cloud, no subscription.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Kinetic Revival")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if bluetooth.state == .scanning {
                    Button("Stop") { bluetooth.stopScanning() }
                } else {
                    Button("Scan") { bluetooth.startScanning() }
                        .disabled(!canScan)
                }
            }
        }
        .errorBanner(bluetooth.lastError, dismiss: bluetooth.dismissError)
    }

    @ViewBuilder
    private var statusSection: some View {
        Section {
            switch bluetooth.state {
            case let .unavailable(reason):
                Label(reason, systemImage: "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(.red)
            case .idle:
                Label("Tap Scan with your trainer plugged in and no other app connected to it.", systemImage: "bicycle")
            case .scanning:
                HStack {
                    ProgressView()
                    Text("Looking for FTMS trainers…")
                }
            case let .connecting(name):
                HStack {
                    ProgressView()
                    Text("Connecting to \(name)…")
                }
            case .connected, .reconnecting, .disconnecting:
                EmptyView()
            }
        }
    }

    private var isConnecting: Bool {
        if case .connecting = bluetooth.state { true } else { false }
    }

    private var canScan: Bool {
        switch bluetooth.state {
        case .idle, .scanning: true
        default: false
        }
    }
}

private struct TrainerRow: View {
    let trainer: DiscoveredTrainer

    var body: some View {
        HStack {
            Image(systemName: "bicycle")
                .foregroundStyle(.tint)
            Text(trainer.name)
                .foregroundStyle(.primary)
            Spacer()
            SignalStrength(rssi: trainer.rssi)
        }
    }
}

private struct SignalStrength: View {
    let rssi: Int

    private var bars: Int {
        switch rssi {
        case (-60)...: 3
        case (-75)...: 2
        default: 1
        }
    }

    var body: some View {
        Image(systemName: "cellularbars", variableValue: Double(bars) / 3)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Signal \(bars) of 3")
    }
}
