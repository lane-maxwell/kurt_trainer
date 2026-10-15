import Foundation
import Testing
@testable import KineticRevival

@MainActor
struct ControlPointClientTests {
    private let client = ControlPointClient(timeout: .milliseconds(200))
    private let link = FakeTrainerLink()

    init() {
        link.deliver = { [client] in client.handleIndication($0) }
        client.attach(link)
    }

    @Test func succeedsWhenTrainerAcknowledges() async throws {
        try await client.send(.setTargetResistance(level: 10))
        #expect(link.writes == [Data(hex: "04 64 00")])
    }

    @Test func returnsResponseParameters() async throws {
        link.responder = { _ in Data(hex: "80 13 01 e8 03 d0 07") }

        let parameters = try await client.send(.startSpinDown)

        #expect(parameters == Data(hex: "e8 03 d0 07"))
    }

    @Test func surfacesRejectionWithResultCode() async {
        link.responder = { Data([0x80, $0[0], 0x03]) }

        await #expect(throws: ControlPointError.rejected(.setTargetPower(watts: 175), .invalidParameter)) {
            try await client.send(.setTargetPower(watts: 175))
        }
    }

    @Test func timesOutWhenTrainerStaysSilent() async {
        link.responder = { _ in nil }

        await #expect(throws: ControlPointError.timedOut(.requestControl)) {
            try await client.send(.requestControl)
        }
    }

    @Test func ignoresResponsesForOtherOpCodes() async {
        link.responder = { _ in Data(hex: "80 05 01") }

        await #expect(throws: ControlPointError.timedOut(.requestControl)) {
            try await client.send(.requestControl)
        }
    }

    @Test func failsFastWhenNotAttached() async {
        client.detach()

        await #expect(throws: ControlPointError.notConnected) {
            try await client.send(.requestControl)
        }
        #expect(link.writes.isEmpty)
    }

    @Test func reportsWriteFailures() async {
        link.failWrites = true

        await #expect(throws: ControlPointError.writeFailed(.requestControl, reason: "radio unavailable")) {
            try await client.send(.requestControl)
        }
    }

    @Test func failsInFlightCommandOnDisconnect() async {
        link.responder = { _ in nil }

        let pending = Task { try await client.send(.requestControl) }
        while link.writes.isEmpty { await Task.yield() }
        client.detach()

        await #expect(throws: ControlPointError.disconnected(.requestControl)) {
            try await pending.value
        }
    }

    @Test func sendsOneCommandAtATime() async throws {
        var pendingAcks: [Data] = []
        link.responder = { request in
            pendingAcks.append(Data([0x80, request[0], 0x01]))
            return nil
        }

        let first = Task { try await client.send(.requestControl) }
        while link.writes.isEmpty { await Task.yield() }
        let second = Task { try await client.send(.setTargetResistance(level: 5)) }
        for _ in 0..<10 { await Task.yield() }

        #expect(link.writes.count == 1, "second command must wait for the first acknowledgement")

        client.handleIndication(pendingAcks.removeFirst())
        while link.writes.count < 2 { await Task.yield() }
        client.handleIndication(pendingAcks.removeFirst())

        _ = try await first.value
        _ = try await second.value
        #expect(link.writes == [Data(hex: "00"), Data(hex: "04 32 00")])
    }
}
