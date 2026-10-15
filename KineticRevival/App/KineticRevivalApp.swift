import SwiftUI

@main
struct KineticRevivalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let app = AppModel.shared

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .appEnvironment(app)
        }
    }
}

extension View {
    func appEnvironment(_ app: AppModel) -> some View {
        environment(app)
            .environment(app.bluetooth)
            .environment(app.routes)
            .environment(app.rides)
    }
}
