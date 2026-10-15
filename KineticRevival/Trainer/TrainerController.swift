import Foundation
import Observation
import os

struct DeviceInfo: Equatable, Sendable {
    var manufacturer: String?
    var model: String?
    var firmware: String?
}

enum TrainerMode: Equatable, Sendable {
    case resistance(level: Double)
    case erg(watts: Int)
    case simulation(gradePercent: Double)
}

/// Progress of an FTMS spin-down calibration, which measures roller/tyre drag so power and
/// resistance stay accurate as tension, tyre pressure and temperature change.
enum SpinDownState: Equatable, Sendable {
    case idle
    case starting
    /// Ride above `target.highKph` until the trainer says to stop. Target is nil if the trainer didn't send one.
    case speedUp(target: SpinDownTarget?)
    case coasting
    case succeeded
    case failed(String)

    var isInProgress: Bool {
        switch self {
        case .starting, .speedUp, .coasting: true
        case .idle, .succeeded, .failed: false
        }
    }
}

enum SimulationStrategy: Equatable, Sendable {
    /// FTMS op code 0x11: the trainer computes resistance from grade and speed.
    case ftms
    /// The trainer refused simulation, so grade is mapped to a resistance level instead.
    case resistanceFallback
}

enum ControlState: Equatable, Sendable {
    case notConnected
    case requesting
    case granted
    case lost
    case failed(String)
}

enum TrainerError: Error, Equatable, LocalizedError {
    case powerTargetUnsupported

    var errorDescription: String? {
        switch self {
        case .powerTargetUnsupported: "This trainer does not advertise ERG (target power) support."
        }
    }
}

/// Trainer state and FTMS control on top of a connected peripheral.
///
/// Bluetooth plumbing lives in `BluetoothManager`; this type only sees bytes, which keeps it testable.
@MainActor
@Observable
final class TrainerController {
    private static let logger = Logger(subsystem: "com.kineticrevival.trainer", category: "Trainer")
    /// A target older than this is not restored after a reconnect; the rider has likely stopped.
    static let restoreWindow: TimeInterval = 60

    private(set) var controlState: ControlState = .notConnected
    /// The last target the trainer acknowledged. Nil until set and after a disconnect.
    private(set) var confirmedMode: TrainerMode?
    /// A target that has been sent but not yet acknowledged.
    private(set) var pendingMode: TrainerMode?
    private(set) var latestData: IndoorBikeData?
    private(set) var metrics = RideMetrics()
    private(set) var features: MachineFeatures?
    private(set) var limits = SafetyLimits()
    private(set) var deviceInfo = DeviceInfo()
    private(set) var lastError: String?
    private(set) var simulationStrategy: SimulationStrategy = .ftms
    private(set) var spinDownState: SpinDownState = .idle

    @ObservationIgnored private let client: ControlPointClient
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var reportedResistanceRange: SupportedRange?
    @ObservationIgnored private var reportedPowerRange: SupportedRange?
    @ObservationIgnored private var interruptedMode: (mode: TrainerMode, at: Date)?

    init(client: ControlPointClient = ControlPointClient(), now: @escaping () -> Date = Date.init) {
        self.client = client
        self.now = now
    }

    var displayedMode: TrainerMode? { pendingMode ?? confirmedMode }

    var supportsErg: Bool {
        features?.targets.contains(.power) ?? true
    }

    var supportsSpinDown: Bool {
        features?.targets.contains(.spinDown) ?? true
    }

    var currentResistanceTarget: Double? {
        if case let .resistance(level) = displayedMode { level } else { nil }
    }

    var currentPowerTarget: Int? {
        if case let .erg(watts) = displayedMode { watts } else { nil }
    }

    // MARK: Commands

    func setResistance(_ level: Double) async {
        await apply(.resistance(level: limits.clampResistance(level)))
    }

    func adjustResistance(by delta: Double) async {
        await setResistance((currentResistanceTarget ?? 0) + delta)
    }

    func setTargetPower(_ watts: Int) async {
        guard supportsErg else {
            lastError = TrainerError.powerTargetUnsupported.localizedDescription
            return
        }
        await apply(.erg(watts: limits.clampPower(watts)))
    }

    func adjustTargetPower(by delta: Int) async {
        let base = currentPowerTarget ?? limits.clampPower(latestData?.powerWatts ?? 100)
        await setTargetPower(base + delta)
    }

    /// Sends a road grade, typically several times a minute during a route ride.
    func setSimulationGrade(_ percent: Double) async {
        let grade = limits.clampGrade(percent)
        if features.map({ !$0.targets.contains(.indoorBikeSimulation) }) ?? false {
            simulationStrategy = .resistanceFallback
        }

        guard simulationStrategy == .ftms else {
            await apply(.resistance(level: limits.resistance(forGradePercent: grade)))
            return
        }

        do {
            try await send(.simulation(gradePercent: grade))
            lastError = nil
        } catch ControlPointError.rejected(_, .opCodeNotSupported) {
            Self.logger.warning("Trainer refused FTMS simulation; falling back to grade → resistance mapping")
            simulationStrategy = .resistanceFallback
            await apply(.resistance(level: limits.resistance(forGradePercent: grade)))
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Drops the brake to zero resistance; the safe state for stopping or disconnecting.
    func releaseResistance() async {
        await apply(.resistance(level: limits.clampResistance(0)))
    }

    // MARK: Calibration

    func startSpinDown() async {
        guard supportsSpinDown else {
            spinDownState = .failed("This trainer doesn't advertise spin-down calibration.")
            return
        }
        guard !spinDownState.isInProgress else { return }

        spinDownState = .starting
        do {
            if controlState != .granted {
                try await requestControl()
            }
            let parameters = try await client.send(.startSpinDown)
            let target = parameters.count >= 4 ? try SpinDownTarget(parameters: parameters) : nil
            // The trainer may already have moved on (e.g. to "stop pedaling") while we awaited the ack.
            if spinDownState == .starting {
                spinDownState = .speedUp(target: target)
            }
            Self.logger.info("Spin-down started; target \(String(describing: target), privacy: .public)")
        } catch {
            spinDownState = .failed(error.localizedDescription)
        }
    }

    /// FTMS has no abort command; the trainer gives up on its own when the rider doesn't spin up.
    func cancelSpinDown() {
        spinDownState = .idle
    }

    private func handleSpinDownStatus(_ status: MachineStatus.SpinDownStatus) {
        switch status {
        case .requested:
            if !spinDownState.isInProgress {
                Self.logger.info("Trainer is requesting a spin-down calibration")
            }
        case .stopPedaling:
            spinDownState = .coasting
        case .success:
            spinDownState = .succeeded
            // Trainers reset their target after calibrating, so the old one is no longer known.
            confirmedMode = nil
        case .error:
            spinDownState = .failed("The trainer couldn't complete the calibration. Get above the target speed, hold it steady, then stop pedaling completely when told.")
        }
    }

    func resetRide() {
        metrics = RideMetrics()
    }

    func dismissError() {
        lastError = nil
    }

    // MARK: Events from the Bluetooth layer

    func trainerDidBecomeReady(writer: ControlPointWriter) async {
        client.attach(writer)
        confirmedMode = nil
        pendingMode = nil
        lastError = nil
        do {
            try await requestControl()
        } catch {
            lastError = error.localizedDescription
            return
        }
        await restoreInterruptedMode()
    }

    /// - Parameter willReconnect: True for an unexpected dropout. The T-6400 drops its brake to zero
    ///   when the link goes, so the current target is remembered and re-sent once the link returns.
    func trainerDidDisconnect(willReconnect: Bool) {
        interruptedMode = willReconnect ? confirmedMode.map { ($0, now()) } : nil
        if !willReconnect { simulationStrategy = .ftms }
        client.detach()
        if spinDownState.isInProgress {
            spinDownState = .failed("The trainer disconnected during calibration.")
        }
        controlState = .notConnected
        confirmedMode = nil
        pendingMode = nil
        latestData = nil
        metrics.pause()
    }

    func handleIndoorBikeData(_ data: Data) {
        do {
            let sample = try IndoorBikeData(data: data)
            latestData = sample
            metrics.record(sample, at: now())
        } catch {
            Self.logger.error("Dropping Indoor Bike Data \(data.hexDescription, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    func handleControlPointIndication(_ data: Data) {
        client.handleIndication(data)
    }

    func handleControlPointWriteFailure(_ error: Error) {
        client.handleWriteFailure(error)
    }

    func handleMachineStatus(_ data: Data) {
        let status: MachineStatus
        do {
            status = try MachineStatus(data: data)
        } catch {
            Self.logger.error("Dropping Machine Status \(data.hexDescription, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }
        Self.logger.info("Machine status: \(String(describing: status), privacy: .public)")

        switch status {
        case .controlPermissionLost:
            controlState = .lost
        case .reset:
            confirmedMode = nil
            controlState = .lost
        case let .targetResistanceChanged(level) where pendingMode == nil:
            confirmedMode = .resistance(level: level)
        case let .targetPowerChanged(watts) where pendingMode == nil:
            confirmedMode = .erg(watts: watts)
        case let .spinDown(status):
            handleSpinDownStatus(status)
        default:
            break
        }
    }

    func handleMachineFeatures(_ data: Data) {
        do {
            features = try MachineFeatures(data: data)
        } catch {
            Self.logger.error("Unreadable Machine Feature \(data.hexDescription, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    func handleSupportedResistanceRange(_ data: Data) {
        reportedResistanceRange = try? SupportedRange(data: data, scale: 0.1, characteristic: "Supported Resistance Level Range")
        updateLimits()
    }

    func handleSupportedPowerRange(_ data: Data) {
        reportedPowerRange = try? SupportedRange(data: data, scale: 1, characteristic: "Supported Power Range")
        updateLimits()
    }

    func updateDeviceInfo(_ update: (inout DeviceInfo) -> Void) {
        update(&deviceInfo)
    }

    // MARK: Private

    private func updateLimits() {
        limits = SafetyLimits(reportedResistance: reportedResistanceRange, reportedPower: reportedPowerRange)
    }

    private func restoreInterruptedMode() async {
        guard let interrupted = interruptedMode else { return }
        interruptedMode = nil

        let age = now().timeIntervalSince(interrupted.at)
        guard age <= Self.restoreWindow else {
            Self.logger.info("Not restoring \(String(describing: interrupted.mode), privacy: .public); link was down \(Int(age))s")
            return
        }
        guard interrupted.mode != .resistance(level: 0) else { return }

        Self.logger.info("Restoring \(String(describing: interrupted.mode), privacy: .public) after reconnect")
        await apply(interrupted.mode)
    }

    private func requestControl() async throws {
        controlState = .requesting
        do {
            try await client.send(.requestControl)
            controlState = .granted
        } catch {
            controlState = .failed(error.localizedDescription)
            throw error
        }
    }

    private func apply(_ mode: TrainerMode) async {
        do {
            try await send(mode)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func send(_ mode: TrainerMode) async throws {
        let command: ControlPointCommand = switch mode {
        case let .resistance(level): .setTargetResistance(level: level)
        case let .erg(watts): .setTargetPower(watts: watts)
        case let .simulation(grade): .setIndoorBikeSimulation(SimulationParameters(gradePercent: grade))
        }

        pendingMode = mode
        defer { if pendingMode == mode { pendingMode = nil } }

        if controlState != .granted {
            try await requestControl()
        }
        do {
            try await client.send(command)
        } catch ControlPointError.rejected(_, .controlNotPermitted) {
            // Another app or a trainer reset took control away; reclaim it once and retry.
            try await requestControl()
            try await client.send(command)
        }
        confirmedMode = mode
    }
}
