import SwiftUI

struct RootView: View {
    @Environment(BluetoothManager.self) private var bluetooth

    var body: some View {
        NavigationStack {
            Group {
                if bluetooth.state.isLinked {
                    DashboardView()
                } else {
                    TrainerPickerView()
                }
            }
        }
    }
}
