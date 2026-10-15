import CoreBluetooth

@MainActor
enum FTMSIdentifiers {
    static let fitnessMachineService = CBUUID(string: "1826")
    static let deviceInformationService = CBUUID(string: "180A")

    static let machineFeature = CBUUID(string: "2ACC")
    static let indoorBikeData = CBUUID(string: "2AD2")
    static let supportedResistanceLevelRange = CBUUID(string: "2AD6")
    static let supportedPowerRange = CBUUID(string: "2AD8")
    static let controlPoint = CBUUID(string: "2AD9")
    static let machineStatus = CBUUID(string: "2ADA")

    static let manufacturerName = CBUUID(string: "2A29")
    static let modelNumber = CBUUID(string: "2A24")
    static let firmwareRevision = CBUUID(string: "2A26")
}
