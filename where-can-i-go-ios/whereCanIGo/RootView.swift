import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appState.needsPassportSelection {
                PassportPickerView(isFirstLaunch: true)
            } else {
                ContentView()
            }
        }
    }
}
