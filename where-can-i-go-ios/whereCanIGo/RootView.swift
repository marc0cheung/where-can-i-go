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
        .alert("Unable to Protect Visa Attachments", isPresented: Binding(
            get: { appState.attachmentProtectionError != nil },
            set: { if !$0 { appState.attachmentProtectionError = nil } }
        )) {
            Button("Retry") { appState.protectVisaAttachments() }
            Button("OK", role: .cancel) {}
        } message: {
            Text(appState.attachmentProtectionError ?? "")
        }
    }
}
