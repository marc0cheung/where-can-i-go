import SwiftUI

@main
struct whereCanIGoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var profileStore = UserProfileStore()
    @StateObject private var friendStore = FriendStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .background(HingeObserver())
                .environmentObject(appState)
                .environmentObject(profileStore)
                .environmentObject(friendStore)
                .task { await appState.bootstrap() }
                .onOpenURL { url in
                    guard url.isFileURL else { return }
                    friendStore.incomingCardURL = url
                }
        }
    }
}
