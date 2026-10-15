import SwiftUI

struct MainTabView: View {
    @Environment(BluetoothManager.self) private var bluetooth

    var body: some View {
        TabView {
            RoutesView()
                .tabItem { Label("Routes", systemImage: "map") }
            RootView()
                .tabItem { Label("Trainer", systemImage: "bicycle") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        // A ride dashboard is useless if the screen locks mid-interval.
        .onChange(of: bluetooth.state.isLinked, initial: true) { _, isLinked in
            UIApplication.shared.isIdleTimerDisabled = isLinked
        }
    }
}
