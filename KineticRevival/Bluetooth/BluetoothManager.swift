@preconcurrency import CoreBluetooth
import Foundation
import Observation
import os

struct DiscoveredTrainer: Identifiable, Equatable {
    let id: UUID
    var name: String
    var rssi: Int
}

enum ConnectionState: Equatable {
    case unavailable(String)
    case idle
    case scanning
    case connecting(name: String)
    case connected(name: String)
    case reconnecting(name: String)
    case disconnecting

    var isLinked: Bool {
        switch self {
        case .connected, .reconnecting, .disconnecting: true
        default: false
        }
    }
}

enum BluetoothError: Error, LocalizedError {
    case controlPointUnavailable

    var errorDescription: String? {
        switch self {
        case .controlPointUnavailable: "The trainer's FTMS control point is not available."
        }
    }
}

/// Discovers FTMS trainers, maintains the connection, and routes GATT traffic to `TrainerController`.
@MainActor
@Observable
final class BluetoothManager: NSObject {
    private static let logger = Logger(subsystem: "com.kineticrevival.trainer", category: "Bluetooth")
    private static let rememberedTrainerKey = "rememberedTrainerIdentifier"

    private(set) var state: ConnectionState = .idle
    private(set) var discovered: [DiscoveredTrainer] = []
    private(set) var lastError: String?

    let trainer: TrainerController

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var controlPoint: CBCharacteristic?
    @ObservationIgnored private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var isUserDisconnect = false
    @ObservationIgnored private let defaults: UserDefaults

    init(trainer: TrainerController, defaults: UserDefaults = .standard) {
        self.trainer = trainer
        self.defaults = defaults
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    var rememberedTrainerID: UUID? {
        defaults.string(forKey: Self.rememberedTrainerKey).flatMap(UUID.init(uuidString:))
    }

    // MARK: User actions

    func startScanning() {
        guard central.state == .poweredOn else { return }
        discovered = []
        discoveredPeripherals = [:]
        lastError = nil
        state = .scanning
        central.scanForPeripherals(withServices: [FTMSIdentifiers.fitnessMachineService])
        Self.logger.info("Scanning for FTMS trainers")
    }

    func stopScanning() {
        central.stopScan()
        if state == .scanning { state = .idle }
    }

    func connect(to trainer: DiscoveredTrainer) {
        guard let peripheral = discoveredPeripherals[trainer.id] else { return }
        central.stopScan()
        connect(peripheral, as: .connecting(name: trainer.name))
    }

    /// Releases resistance before dropping the link, so the trainer isn't left braking.
    func disconnect() async {
        guard let peripheral else { return }
        isUserDisconnect = true
        state = .disconnecting

        // Bounded by the control point timeout, so a silent trainer can't block the disconnect.
        if trainer.controlState == .granted {
            await trainer.releaseResistance()
        }
        central.cancelPeripheralConnection(peripheral)
    }

    func cancelReconnect() {
        guard let peripheral, case .reconnecting = state else { return }
        isUserDisconnect = true
        central.cancelPeripheralConnection(peripheral)
    }

    func forgetTrainer() {
        defaults.removeObject(forKey: Self.rememberedTrainerKey)
    }

    func dismissError() {
        lastError = nil
    }

    // MARK: Private

    private func connect(_ peripheral: CBPeripheral, as newState: ConnectionState) {
        isUserDisconnect = false
        self.peripheral = peripheral
        peripheral.delegate = self
        state = newState
        // CoreBluetooth connection requests never time out, which is what we want for reconnects:
        // the link comes back as soon as the trainer is in range and powered.
        central.connect(peripheral)
    }

    private func reconnectToRememberedTrainer() {
        guard peripheral == nil,
              let id = rememberedTrainerID,
              let remembered = central.retrievePeripherals(withIdentifiers: [id]).first
        else { return }
        Self.logger.info("Reconnecting to remembered trainer \(id, privacy: .public)")
        connect(remembered, as: .reconnecting(name: remembered.name ?? "Trainer"))
    }

    private func handleLinkLost(error: Error?) {
        controlPoint = nil
        trainer.trainerDidDisconnect(willReconnect: !isUserDisconnect)

        guard let peripheral else { return }
        if isUserDisconnect {
            self.peripheral = nil
            state = .idle
            Self.logger.info("Disconnected from trainer")
        } else if central.state == .poweredOn {
            Self.logger.warning("Lost trainer connection: \(error?.localizedDescription ?? "no error", privacy: .public)")
            connect(peripheral, as: .reconnecting(name: peripheral.name ?? "Trainer"))
        } else {
            // Connecting while the radio is off is an API misuse; the remembered trainer is
            // reconnected when Bluetooth powers back on.
            self.peripheral = nil
        }
    }

    private func displayName(for peripheral: CBPeripheral, advertisementData: [String: Any]) -> String {
        advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Unnamed trainer"
    }
}

extension BluetoothManager: ControlPointWriter {
    func writeControlPoint(_ data: Data) throws {
        guard let peripheral, let controlPoint, peripheral.state == .connected else {
            throw BluetoothError.controlPointUnavailable
        }
        peripheral.writeValue(data, for: controlPoint, type: .withResponse)
    }
}

extension BluetoothManager: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if case .unavailable = state { state = .idle }
            reconnectToRememberedTrainer()
        case .poweredOff:
            if peripheral != nil { handleLinkLost(error: nil) }
            state = .unavailable("Bluetooth is turned off.")
        case .unauthorized:
            state = .unavailable("Bluetooth permission was denied. Enable it in Settings → Kinetic Revival.")
        case .unsupported:
            state = .unavailable("This device does not support Bluetooth Low Energy.")
        case .resetting, .unknown:
            break
        @unknown default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        discoveredPeripherals[peripheral.identifier] = peripheral
        let entry = DiscoveredTrainer(
            id: peripheral.identifier,
            name: displayName(for: peripheral, advertisementData: advertisementData),
            rssi: RSSI.intValue
        )
        if let index = discovered.firstIndex(where: { $0.id == entry.id }) {
            discovered[index] = entry
        } else {
            discovered.append(entry)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Self.logger.info("Connected to \(peripheral.identifier, privacy: .public); discovering services")
        defaults.set(peripheral.identifier.uuidString, forKey: Self.rememberedTrainerKey)
        peripheral.discoverServices([
            FTMSIdentifiers.fitnessMachineService,
            FTMSIdentifiers.deviceInformationService,
        ])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        lastError = "Could not connect: \(error?.localizedDescription ?? "unknown error")"
        if case .reconnecting = state, !isUserDisconnect {
            connect(peripheral, as: state)
        } else {
            self.peripheral = nil
            state = .idle
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        handleLinkLost(error: error)
    }
}

extension BluetoothManager: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            lastError = "Service discovery failed: \(error.localizedDescription)"
            return
        }
        guard let services = peripheral.services,
              services.contains(where: { $0.uuid == FTMSIdentifiers.fitnessMachineService })
        else {
            lastError = "This device does not expose the Fitness Machine Service."
            return
        }
        services.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            lastError = "Characteristic discovery failed: \(error.localizedDescription)"
            return
        }
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case FTMSIdentifiers.controlPoint:
                controlPoint = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            case FTMSIdentifiers.indoorBikeData, FTMSIdentifiers.machineStatus:
                peripheral.setNotifyValue(true, for: characteristic)
            case FTMSIdentifiers.machineFeature,
                 FTMSIdentifiers.supportedResistanceLevelRange,
                 FTMSIdentifiers.supportedPowerRange,
                 FTMSIdentifiers.manufacturerName,
                 FTMSIdentifiers.modelNumber,
                 FTMSIdentifiers.firmwareRevision:
                peripheral.readValue(for: characteristic)
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            lastError = "Could not subscribe to \(characteristic.uuid): \(error.localizedDescription)"
            return
        }
        // Commands can only be acknowledged once control point indications are on.
        guard characteristic.uuid == FTMSIdentifiers.controlPoint, characteristic.isNotifying else { return }
        state = .connected(name: peripheral.name ?? "Trainer")
        Task { await trainer.trainerDidBecomeReady(writer: self) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            Self.logger.error("Read of \(characteristic.uuid, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let value = characteristic.value else { return }

        switch characteristic.uuid {
        case FTMSIdentifiers.indoorBikeData:
            trainer.handleIndoorBikeData(value)
        case FTMSIdentifiers.controlPoint:
            trainer.handleControlPointIndication(value)
        case FTMSIdentifiers.machineStatus:
            trainer.handleMachineStatus(value)
        case FTMSIdentifiers.machineFeature:
            trainer.handleMachineFeatures(value)
        case FTMSIdentifiers.supportedResistanceLevelRange:
            trainer.handleSupportedResistanceRange(value)
        case FTMSIdentifiers.supportedPowerRange:
            trainer.handleSupportedPowerRange(value)
        case FTMSIdentifiers.manufacturerName:
            trainer.updateDeviceInfo { $0.manufacturer = String(decoding: value, as: UTF8.self) }
        case FTMSIdentifiers.modelNumber:
            trainer.updateDeviceInfo { $0.model = String(decoding: value, as: UTF8.self) }
        case FTMSIdentifiers.firmwareRevision:
            trainer.updateDeviceInfo { $0.firmware = String(decoding: value, as: UTF8.self) }
        default:
            break
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let error, characteristic.uuid == FTMSIdentifiers.controlPoint else { return }
        trainer.handleControlPointWriteFailure(error)
    }
}
