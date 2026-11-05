import SwiftUI
import UIKit
import OSLog

/// Orientation masks for foldable screens and devices without a hinge.
@MainActor
enum OrientationPolicy {
    static func supportedOrientations(
        for idiom: UIUserInterfaceIdiom, isHingeClosed: Bool? = nil
    ) -> UIInterfaceOrientationMask {
        if let isHingeClosed { return isHingeClosed ? .portrait : .all }
        return idiom == .pad ? .all : .allButUpsideDown
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowApplication {
            configuration.delegateClass = OrientationSceneDelegate.self
        }
        return configuration
    }

    // Pre-iOS 27 path; iOS 27 asks the scene delegate below instead.
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        let idiom = window?.traitCollection.userInterfaceIdiom ?? UIDevice.current.userInterfaceIdiom
        return MainActor.assumeIsolated { OrientationPolicy.supportedOrientations(for: idiom) }
    }
}

final class OrientationSceneDelegate: NSObject, UIWindowSceneDelegate {
    private static let logger = Logger(subsystem: "com.marcocheung.whereCanIGo", category: "Orientation")
    private var isHingeClosed: Bool?

    @available(iOS 27.0, *)
    func supportedInterfaceOrientations(for windowScene: UIWindowScene) -> UIInterfaceOrientationMask {
        OrientationPolicy.supportedOrientations(
            for: windowScene.traitCollection.userInterfaceIdiom, isHingeClosed: isHingeClosed)
    }

    @available(iOS 27.1, *)
    func updateHinge(isClosed: Bool, in scene: UIWindowScene) {
        guard isClosed != isHingeClosed else { return }
        isHingeClosed = isClosed

        for window in scene.windows {
            var controller = window.rootViewController
            while let current = controller {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller = current.presentedViewController
            }
        }
        // Replace the previous geometry preference in both directions, including
        // the portrait-only request made while using the outer display.
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: supportedInterfaceOrientations(for: scene))) { error in
            Self.logger.error("Unable to update interface orientations: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Reports hinge updates to the owning scene, without affecting other windows.
struct HingeObserver: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        if #available(iOS 27.1, *) {
            view.addInteraction(UIHingeInteraction { interaction, update in
                // A nil hinge is a hierarchy change, not a fold or unfold event.
                guard let hinge = update.hinge, hinge.status != .unknown,
                      let scene = interaction.view?.window?.windowScene,
                      let delegate = scene.delegate as? OrientationSceneDelegate else { return }
                delegate.updateHinge(isClosed: hinge.status == .closed, in: scene)
            })
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
