import Foundation
import Observation

/// App-wide state shared by every scene: the phone's window and, when AirPlay is on, the TV.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let bluetooth: BluetoothManager
    let routes: RouteLibrary
    let rides: RideStore
    /// The route ride in progress, if any. Set from the phone; mirrored on the TV.
    var activeRide: RideSession?
    /// True while a TV (or any external display) is showing the dedicated ride view.
    private(set) var isExternalDisplayConnected = false

    init(
        bluetooth: BluetoothManager = BluetoothManager(trainer: TrainerController()),
        routes: RouteLibrary = RouteLibrary(),
        rides: RideStore = RideStore()
    ) {
        self.bluetooth = bluetooth
        self.routes = routes
        self.rides = rides
    }

    func startRide(on route: Route, with trainer: RideTrainer) {
        activeRide = RideSession(
            route: route,
            trainer: trainer,
            physics: RiderSettings.physicsParameters(),
            difficulty: RiderSettings.difficulty()
        )
    }

    func externalDisplayDidConnect() {
        isExternalDisplayConnected = true
    }

    func externalDisplayDidDisconnect() {
        isExternalDisplayConnected = false
    }
}
