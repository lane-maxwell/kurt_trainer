import os
import SwiftUI
import UIKit

/// Routes AirPlay / external display sessions to a dedicated TV scene instead of mirroring the phone.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        guard connectingSceneSession.role == .windowExternalDisplayNonInteractive else {
            return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        }
        let configuration = UISceneConfiguration(name: "External Display", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = ExternalDisplaySceneDelegate.self
        return configuration
    }
}

final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    private static let logger = Logger(subsystem: "com.kineticrevival.trainer", category: "ExternalDisplay")

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let app = AppModel.shared
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: TVDisplayView().appEnvironment(app))
        window.isHidden = false
        self.window = window
        app.externalDisplayDidConnect()
        Self.logger.info("External display connected: \(windowScene.screen.bounds.debugDescription, privacy: .public)")
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        window = nil
        AppModel.shared.externalDisplayDidDisconnect()
        Self.logger.info("External display disconnected")
    }
}
