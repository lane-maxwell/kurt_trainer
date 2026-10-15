import Foundation
import Testing
@testable import KineticRevival

struct IndoorBikeDataTests {
    @Test func decodesPacketCapturedFromT6400() throws {
        let data = try IndoorBikeData(data: Data(hex: "40 08 c7 00 00 00 fd 03"))

        #expect(data.speedKph == 1.99)
        #expect(data.powerWatts == 0)
        #expect(data.elapsedTimeSeconds == 1021)
        #expect(data.cadenceRpm == nil)
        #expect(data.totalDistanceMeters == nil)
    }

    @Test func decodesEveryOptionalFieldInOrder() throws {
        // Flags 0x1FFE: every field except "more data", so speed is present too.
        let packet = Data(hex: """
            fe 1f \
            10 27 \
            e8 03 \
            b4 00 \
            a0 00 \
            39 30 00 \
            0a 00 \
            c8 00 \
            96 00 \
            01 00 02 00 03 \
            8c \
            32 \
            3c 00 \
            78 00
            """)

        let data = try IndoorBikeData(data: packet)

        #expect(data.speedKph == 100.0)
        #expect(data.averageSpeedKph == 10.0)
        #expect(data.cadenceRpm == 90.0)
        #expect(data.averageCadenceRpm == 80.0)
        #expect(data.totalDistanceMeters == 12345)
        #expect(data.resistanceLevel == 10)
        #expect(data.powerWatts == 200)
        #expect(data.averagePowerWatts == 150)
        #expect(data.heartRateBpm == 140)
        #expect(data.elapsedTimeSeconds == 60)
        #expect(data.remainingTimeSeconds == 120)
    }

    @Test func omitsSpeedWhenMoreDataFlagIsSet() throws {
        let data = try IndoorBikeData(data: Data(hex: "41 00 64 00"))

        #expect(data.speedKph == nil)
        #expect(data.powerWatts == 100)
    }

    @Test func decodesNegativePower() throws {
        let data = try IndoorBikeData(data: Data(hex: "40 00 00 00 f6 ff"))
        #expect(data.powerWatts == -10)
    }

    @Test(arguments: ["", "40", "40 08 c7 00 00 00 fd"])
    func rejectsTruncatedPackets(hex: String) {
        #expect(throws: FTMSParseError.self) {
            try IndoorBikeData(data: Data(hex: hex))
        }
    }
}

struct ControlPointCommandTests {
    @Test func requestControlIsSingleOpCode() {
        #expect(ControlPointCommand.requestControl.encoded == Data(hex: "00"))
    }

    @Test(arguments: [
        (10.0, "04 64 00"),
        (0.0, "04 00 00"),
        (100.0, "04 e8 03"),
        (10.04, "04 64 00"),
        (-1.5, "04 f1 ff"),
    ])
    func encodesResistanceAsTenthsInSint16(level: Double, hex: String) {
        #expect(ControlPointCommand.setTargetResistance(level: level).encoded == Data(hex: hex))
    }

    @Test func encodesTargetPowerInWatts() {
        #expect(ControlPointCommand.setTargetPower(watts: 175).encoded == Data(hex: "05 af 00"))
    }

    @Test func encodesStartSpinDown() {
        #expect(ControlPointCommand.startSpinDown.encoded == Data(hex: "13 01"))
    }

    @Test func encodesIndoorBikeSimulation() {
        let command = ControlPointCommand.setIndoorBikeSimulation(SimulationParameters(gradePercent: 5))
        #expect(command.encoded == Data(hex: "11 00 00 f4 01 28 33"))
    }

    @Test func encodesNegativeGradeSimulation() {
        let command = ControlPointCommand.setIndoorBikeSimulation(SimulationParameters(gradePercent: -2.5))
        #expect(command.encoded == Data(hex: "11 00 00 06 ff 28 33"))
    }

    @Test func clampsOutOfRangeValuesInsteadOfTrapping() {
        #expect(ControlPointCommand.setTargetPower(watts: 1_000_000).encoded == Data(hex: "05 ff 7f"))
    }
}

struct ControlPointResponseTests {
    @Test func decodesVerifiedSuccessResponse() throws {
        let response = try ControlPointResponse(data: Data(hex: "80 04 01"))
        #expect(response == ControlPointResponse(requestOpCode: 0x04, result: .success))
    }

    @Test func keepsResponseParameters() throws {
        let response = try ControlPointResponse(data: Data(hex: "80 13 01 e8 03 d0 07"))

        #expect(response.parameters == Data(hex: "e8 03 d0 07"))
        #expect(try SpinDownTarget(parameters: response.parameters) == SpinDownTarget(lowKph: 10, highKph: 20))
    }

    @Test func rejectsTruncatedSpinDownTarget() {
        #expect(throws: FTMSParseError.self) { try SpinDownTarget(parameters: Data(hex: "e8 03")) }
    }

    @Test func decodesRejection() throws {
        let response = try ControlPointResponse(data: Data(hex: "80 05 05"))
        #expect(response.result == .controlNotPermitted)
    }

    @Test(arguments: ["04 64 00", "80 04 09", "80 04", ""])
    func rejectsMalformedResponses(hex: String) {
        #expect(throws: FTMSParseError.self) {
            try ControlPointResponse(data: Data(hex: hex))
        }
    }
}

struct MachineStatusTests {
    @Test func decodesResistanceChangeCapturedFromT6400() throws {
        #expect(try MachineStatus(data: Data(hex: "07 64 00")) == .targetResistanceChanged(level: 10.0))
    }

    @Test func decodesSpecCompliantSingleByteResistance() throws {
        #expect(try MachineStatus(data: Data(hex: "07 64")) == .targetResistanceChanged(level: 10.0))
    }

    @Test func decodesOtherStatuses() throws {
        #expect(try MachineStatus(data: Data(hex: "08 af 00")) == .targetPowerChanged(watts: 175))
        #expect(try MachineStatus(data: Data(hex: "ff")) == .controlPermissionLost)
        #expect(try MachineStatus(data: Data(hex: "01")) == .reset)
        #expect(try MachineStatus(data: Data(hex: "14 01")) == .spinDown(.requested))
        #expect(try MachineStatus(data: Data(hex: "14 04")) == .spinDown(.stopPedaling))
        #expect(try MachineStatus(data: Data(hex: "12")) == .other(opCode: 0x12))
    }

    @Test func rejectsEmptyAndTruncatedStatuses() {
        #expect(throws: FTMSParseError.self) { try MachineStatus(data: Data()) }
        #expect(throws: FTMSParseError.self) { try MachineStatus(data: Data(hex: "14 09")) }
        #expect(throws: FTMSParseError.self) { try MachineStatus(data: Data(hex: "14")) }
        #expect(throws: FTMSParseError.self) { try MachineStatus(data: Data(hex: "07")) }
    }
}

struct MachineFeaturesTests {
    @Test func decodesFeaturesReportedByT6400() throws {
        let features = try MachineFeatures(data: Data(hex: "80 54 00 00 0c e0 00 00"))

        #expect(features.targets.contains([.resistance, .power, .indoorBikeSimulation, .wheelCircumference, .spinDown]))
        #expect(features.measurements.contains([.power, .elapsedTime, .resistanceLevel]))
        #expect(!features.measurements.contains(.cadence))
    }

    @Test func rejectsShortPayload() {
        #expect(throws: FTMSParseError.self) {
            try MachineFeatures(data: Data(hex: "80 54 00 00"))
        }
    }
}

struct SupportedRangeTests {
    @Test func decodesResistanceRangeReportedByT6400() throws {
        let range = try SupportedRange(data: Data(hex: "30 f8 d0 07 01 00"), scale: 0.1, characteristic: "test")
        #expect(range == SupportedRange(minimum: -200, maximum: 200, increment: 0.1))
    }

    @Test func decodesPowerRangeReportedByT6400() throws {
        let range = try SupportedRange(data: Data(hex: "60 f0 a0 0f 01 00"), scale: 1, characteristic: "test")
        #expect(range == SupportedRange(minimum: -4000, maximum: 4000, increment: 1))
    }

    @Test func rejectsInvertedRange() {
        #expect(throws: FTMSParseError.self) {
            try SupportedRange(data: Data(hex: "64 00 0a 00 01 00"), scale: 1, characteristic: "test")
        }
    }
}
