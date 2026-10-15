import Foundation
import Testing
@testable import KineticRevival

@MainActor
struct TrainerControllerTests {
    private let clock = TestClock()
    private let trainer: TrainerController
    private let link = FakeTrainerLink()

    init() {
        trainer = TrainerController(client: ControlPointClient(timeout: .milliseconds(200)), now: { [clock] in clock.now })
        link.deliver = { [trainer] in trainer.handleControlPointIndication($0) }
    }

    @Test func requestsControlWhenTrainerBecomesReady() async {
        await trainer.trainerDidBecomeReady(writer: link)

        #expect(trainer.controlState == .granted)
        #expect(link.writes == [Data(hex: "00")])
        #expect(trainer.confirmedMode == nil)
    }

    @Test func reportsFailedControlRequest() async {
        link.responder = { _ in Data(hex: "80 00 04") }

        await trainer.trainerDidBecomeReady(writer: link)

        guard case .failed = trainer.controlState else {
            Issue.record("expected failed control state, got \(trainer.controlState)")
            return
        }
        #expect(trainer.lastError != nil)
    }

    @Test func setsResistanceWithinSafetyLimits() async {
        await trainer.trainerDidBecomeReady(writer: link)

        await trainer.setResistance(250)

        #expect(link.writes.last == Data(hex: "04 e8 03"))
        #expect(trainer.confirmedMode == .resistance(level: 100))
        #expect(trainer.pendingMode == nil)
    }

    @Test func adjustsFromCurrentTarget() async {
        await trainer.trainerDidBecomeReady(writer: link)
        await trainer.setResistance(10)

        await trainer.adjustResistance(by: 5)

        #expect(trainer.currentResistanceTarget == 15)
        #expect(link.writes.last == Data(hex: "04 96 00"))
    }

    @Test func keepsPreviousTargetWhenCommandIsRejected() async {
        await trainer.trainerDidBecomeReady(writer: link)
        await trainer.setResistance(10)
        link.responder = { Data([0x80, $0[0], 0x04]) }

        await trainer.setResistance(20)

        #expect(trainer.confirmedMode == .resistance(level: 10))
        #expect(trainer.lastError != nil)
    }

    @Test func reclaimsControlOnceWhenNotPermitted() async {
        await trainer.trainerDidBecomeReady(writer: link)
        var rejectedOnce = false
        link.responder = { request in
            if request[0] == 0x04, !rejectedOnce {
                rejectedOnce = true
                return Data(hex: "80 04 05")
            }
            return Data([0x80, request[0], 0x01])
        }

        await trainer.setResistance(10)

        #expect(link.writes == [Data(hex: "00"), Data(hex: "04 64 00"), Data(hex: "00"), Data(hex: "04 64 00")])
        #expect(trainer.confirmedMode == .resistance(level: 10))
        #expect(trainer.lastError == nil)
    }

    @Test func requestsControlAgainAfterTrainerRevokesIt() async {
        await trainer.trainerDidBecomeReady(writer: link)
        trainer.handleMachineStatus(Data(hex: "ff"))
        #expect(trainer.controlState == .lost)

        await trainer.setResistance(10)

        #expect(link.writes == [Data(hex: "00"), Data(hex: "00"), Data(hex: "04 64 00")])
        #expect(trainer.controlState == .granted)
    }

    @Test func refusesErgWhenTrainerDoesNotSupportIt() async {
        await trainer.trainerDidBecomeReady(writer: link)
        trainer.handleMachineFeatures(Data(hex: "80 54 00 00 04 00 00 00"))

        await trainer.setTargetPower(150)

        #expect(link.writes == [Data(hex: "00")])
        #expect(trainer.lastError == TrainerError.powerTargetUnsupported.localizedDescription)
    }

    @Test func setsErgTargetWithinLimits() async {
        await trainer.trainerDidBecomeReady(writer: link)
        trainer.handleMachineFeatures(Data(hex: "80 54 00 00 0c e0 00 00"))

        await trainer.setTargetPower(1000)

        #expect(link.writes.last == Data(hex: "05 90 01"))
        #expect(trainer.confirmedMode == .erg(watts: 400))
    }

    @Test func releaseReturnsResistanceToZero() async {
        await trainer.trainerDidBecomeReady(writer: link)
        await trainer.setResistance(30)

        await trainer.releaseResistance()

        #expect(link.writes.last == Data(hex: "04 00 00"))
        #expect(trainer.confirmedMode == .resistance(level: 0))
    }

    @Test func forgetsTargetAndControlOnDisconnect() async {
        await trainer.trainerDidBecomeReady(writer: link)
        await trainer.setResistance(30)
        trainer.handleIndoorBikeData(Data(hex: "40 08 c7 00 00 00 fd 03"))

        trainer.trainerDidDisconnect(willReconnect: false)

        #expect(trainer.controlState == .notConnected)
        #expect(trainer.confirmedMode == nil)
        #expect(trainer.latestData == nil)
    }

    @Test func tracksTargetChangesReportedByTrainer() {
        trainer.handleMachineStatus(Data(hex: "07 64 00"))
        #expect(trainer.confirmedMode == .resistance(level: 10))
    }

    @Test func narrowsLimitsFromReportedRanges() {
        trainer.handleSupportedResistanceRange(Data(hex: "00 00 90 01 01 00"))
        #expect(trainer.limits.resistanceRange == 0...40)
    }

    @Test func keepsLastGoodSampleWhenPacketIsMalformed() {
        trainer.handleIndoorBikeData(Data(hex: "40 08 c7 00 00 00 fd 03"))
        trainer.handleIndoorBikeData(Data(hex: "40 08"))

        #expect(trainer.latestData?.speedKph == 1.99)
    }

    // MARK: Reconnect restore (the T-6400 drops to zero resistance whenever the link goes)

    @Test func restoresResistanceAfterQuickDropout() async {
        await trainer.trainerDidBecomeReady(writer: link)
        await trainer.setResistance(30)

        trainer.trainerDidDisconnect(willReconnect: true)
        clock.advance(by: 10)
        await trainer.trainerDidBecomeReady(writer: link)

        #expect(link.writes.suffix(2) == [Data(hex: "00"), Data(hex: "04 2c 01")])
        #expect(trainer.confirmedMode == .resistance(level: 30))
    }

    @Test func restoresErgTargetAfterQuickDropout() async {
        await trainer.trainerDidBecomeReady(writer: link)
        await trainer.setTargetPower(150)

        trainer.trainerDidDisconnect(willReconnect: true)
        await trainer.trainerDidBecomeReady(writer: link)

        #expect(link.writes.last == Data(hex: "05 96 00"))
        #expect(trainer.confirmedMode == .erg(watts: 150))
    }

    @Test func doesNotRestoreAfterUserDisconnect() async {
        await trainer.trainerDidBecomeReady(writer: link)
        await trainer.setResistance(30)

        trainer.trainerDidDisconnect(willReconnect: false)
        await trainer.trainerDidBecomeReady(writer: link)

        #expect(link.writes.last == Data(hex: "00"))
        #expect(trainer.confirmedMode == nil)
    }

    @Test func doesNotRestoreStaleTarget() async {
        await trainer.trainerDidBecomeReady(writer: link)
        await trainer.setResistance(30)

        trainer.trainerDidDisconnect(willReconnect: true)
        clock.advance(by: TrainerController.restoreWindow + 1)
        await trainer.trainerDidBecomeReady(writer: link)

        #expect(link.writes.last == Data(hex: "00"))
        #expect(trainer.confirmedMode == nil)
    }

    @Test func restoresOnlyOnce() async {
        await trainer.trainerDidBecomeReady(writer: link)
        await trainer.setResistance(30)
        trainer.trainerDidDisconnect(willReconnect: true)
        await trainer.trainerDidBecomeReady(writer: link)
        let writesAfterRestore = link.writes.count

        trainer.trainerDidDisconnect(willReconnect: false)
        await trainer.trainerDidBecomeReady(writer: link)

        #expect(link.writes.count == writesAfterRestore + 1)
    }

    @Test func skipsRestoreWhenTargetWasAlreadyZero() async {
        await trainer.trainerDidBecomeReady(writer: link)
        await trainer.releaseResistance()

        trainer.trainerDidDisconnect(willReconnect: true)
        await trainer.trainerDidBecomeReady(writer: link)

        #expect(link.writes.last == Data(hex: "00"))
    }

    @Test func skipsRestoreWhenControlIsRefused() async {
        await trainer.trainerDidBecomeReady(writer: link)
        await trainer.setResistance(30)
        trainer.trainerDidDisconnect(willReconnect: true)
        link.responder = { Data([0x80, $0[0], 0x04]) }

        await trainer.trainerDidBecomeReady(writer: link)

        #expect(link.writes.last == Data(hex: "00"))
        #expect(trainer.lastError != nil)
    }

    @Test func reportsFailedRestore() async {
        await trainer.trainerDidBecomeReady(writer: link)
        await trainer.setResistance(30)
        trainer.trainerDidDisconnect(willReconnect: true)
        link.responder = { request in Data([0x80, request[0], request[0] == 0x04 ? 0x04 : 0x01]) }

        await trainer.trainerDidBecomeReady(writer: link)

        #expect(trainer.confirmedMode == nil)
        #expect(trainer.lastError != nil)
    }

    // MARK: Simulation

    @Test func sendsSimulatedGrade() async {
        await trainer.trainerDidBecomeReady(writer: link)

        await trainer.setSimulationGrade(4.04)

        #expect(link.writes.last == Data(hex: "11 00 00 90 01 28 33"))
        #expect(trainer.confirmedMode == .simulation(gradePercent: 4))
        #expect(trainer.simulationStrategy == .ftms)
    }

    @Test func clampsSimulatedGrade() async {
        await trainer.trainerDidBecomeReady(writer: link)

        await trainer.setSimulationGrade(35)

        #expect(trainer.confirmedMode == .simulation(gradePercent: 20))
    }

    @Test func fallsBackToResistanceWhenSimulationIsRefused() async {
        await trainer.trainerDidBecomeReady(writer: link)
        link.responder = { request in Data([0x80, request[0], request[0] == 0x11 ? 0x02 : 0x01]) }

        await trainer.setSimulationGrade(5)
        await trainer.setSimulationGrade(2)

        #expect(trainer.simulationStrategy == .resistanceFallback)
        #expect(trainer.confirmedMode == .resistance(level: 16))
        #expect(link.writes.filter { $0.first == 0x11 }.count == 1, "should stop trying simulation once refused")
        #expect(trainer.lastError == nil)
    }

    @Test func usesFallbackWhenTrainerDoesNotAdvertiseSimulation() async {
        await trainer.trainerDidBecomeReady(writer: link)
        trainer.handleMachineFeatures(Data(hex: "80 54 00 00 0c 00 00 00"))

        await trainer.setSimulationGrade(-10)

        #expect(link.writes.last == Data(hex: "04 00 00"))
        #expect(trainer.simulationStrategy == .resistanceFallback)
    }

    @Test func retriesSimulationWithNextTrainer() async {
        await trainer.trainerDidBecomeReady(writer: link)
        link.responder = { request in Data([0x80, request[0], request[0] == 0x11 ? 0x02 : 0x01]) }
        await trainer.setSimulationGrade(5)

        trainer.trainerDidDisconnect(willReconnect: false)

        #expect(trainer.simulationStrategy == .ftms)
    }

    // MARK: Spin-down calibration

    private func respondToSpinDown(with parameters: String) {
        link.responder = { request in
            request[0] == 0x13 ? Data(hex: "80 13 01" + (parameters.isEmpty ? "" : " " + parameters)) : Data([0x80, request[0], 0x01])
        }
    }

    @Test func spinDownWalksThroughTrainerStatuses() async {
        await trainer.trainerDidBecomeReady(writer: link)
        await trainer.setResistance(20)
        respondToSpinDown(with: "e8 03 d0 07")

        await trainer.startSpinDown()
        #expect(link.writes.last == Data(hex: "13 01"))
        #expect(trainer.spinDownState == .speedUp(target: SpinDownTarget(lowKph: 10, highKph: 20)))

        trainer.handleMachineStatus(Data(hex: "14 04"))
        #expect(trainer.spinDownState == .coasting)

        trainer.handleMachineStatus(Data(hex: "14 02"))
        #expect(trainer.spinDownState == .succeeded)
        #expect(trainer.confirmedMode == nil)
    }

    @Test func spinDownWorksWithoutTargetSpeeds() async {
        await trainer.trainerDidBecomeReady(writer: link)
        respondToSpinDown(with: "")

        await trainer.startSpinDown()

        #expect(trainer.spinDownState == .speedUp(target: nil))
    }

    @Test func spinDownRequestsControlFirst() async {
        await trainer.trainerDidBecomeReady(writer: link)
        trainer.handleMachineStatus(Data(hex: "ff"))
        respondToSpinDown(with: "e8 03 d0 07")

        await trainer.startSpinDown()

        #expect(link.writes.suffix(2) == [Data(hex: "00"), Data(hex: "13 01")])
    }

    @Test func spinDownReportsTrainerError() async {
        await trainer.trainerDidBecomeReady(writer: link)
        respondToSpinDown(with: "e8 03 d0 07")
        await trainer.startSpinDown()

        trainer.handleMachineStatus(Data(hex: "14 03"))

        guard case .failed = trainer.spinDownState else {
            Issue.record("expected failure, got \(trainer.spinDownState)")
            return
        }
    }

    @Test func spinDownReportsRejection() async {
        await trainer.trainerDidBecomeReady(writer: link)
        link.responder = { request in Data([0x80, request[0], request[0] == 0x13 ? 0x04 : 0x01]) }

        await trainer.startSpinDown()

        guard case .failed = trainer.spinDownState else {
            Issue.record("expected failure, got \(trainer.spinDownState)")
            return
        }
    }

    @Test func refusesSpinDownWhenNotAdvertised() async {
        await trainer.trainerDidBecomeReady(writer: link)
        trainer.handleMachineFeatures(Data(hex: "80 54 00 00 0c 60 00 00"))

        await trainer.startSpinDown()

        #expect(!trainer.supportsSpinDown)
        #expect(link.writes == [Data(hex: "00")])
        guard case .failed = trainer.spinDownState else {
            Issue.record("expected failure, got \(trainer.spinDownState)")
            return
        }
    }

    @Test func disconnectFailsSpinDownInProgress() async {
        await trainer.trainerDidBecomeReady(writer: link)
        respondToSpinDown(with: "e8 03 d0 07")
        await trainer.startSpinDown()

        trainer.trainerDidDisconnect(willReconnect: true)

        guard case .failed = trainer.spinDownState else {
            Issue.record("expected failure, got \(trainer.spinDownState)")
            return
        }
    }

    @Test func cancelReturnsToIdle() async {
        await trainer.trainerDidBecomeReady(writer: link)
        respondToSpinDown(with: "e8 03 d0 07")
        await trainer.startSpinDown()

        trainer.cancelSpinDown()

        #expect(trainer.spinDownState == .idle)
    }
}
