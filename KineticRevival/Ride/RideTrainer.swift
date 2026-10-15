import Foundation

/// What a route ride needs from a trainer. `TrainerController` is the real one; `SimulatedRider`
/// stands in when previewing a route without hardware.
@MainActor
protocol RideTrainer: AnyObject {
    var latestData: IndoorBikeData? { get }
    func setSimulationGrade(_ percent: Double) async
    func releaseResistance() async
}

extension TrainerController: RideTrainer {}

/// A pretend rider holding steady power, for trying routes in the simulator or without a trainer.
@MainActor
final class SimulatedRider: RideTrainer {
    let powerWatts: Int
    private(set) var sentGrades: [Double] = []

    init(powerWatts: Int = 200) {
        self.powerWatts = powerWatts
    }

    var latestData: IndoorBikeData? {
        IndoorBikeData(cadenceRpm: 85, powerWatts: powerWatts)
    }

    func setSimulationGrade(_ percent: Double) async {
        sentGrades.append(percent)
    }

    func releaseResistance() async {}
}
