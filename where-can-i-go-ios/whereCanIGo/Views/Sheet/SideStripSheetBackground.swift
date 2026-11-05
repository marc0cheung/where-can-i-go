import SwiftUI
import UIKit

/// Replaces the system sheet's default glass with a fully clear background so
/// the map shows through the side strip. Restores the default when disabled.
struct ClearSheetBackgroundEffect: UIViewRepresentable {
    var isEnabled: Bool

    func makeUIView(context: Context) -> ProbeView { ProbeView() }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.isEnabled = isEnabled
        uiView.apply()
    }

    final class ProbeView: UIView {
        var isEnabled = false
        private let clearEffect = UIColorEffect(color: .clear)

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            // Fold transitions can replace the presentation's detents/effects
            // after updateUIView and didMoveToWindow have already run.
            apply()
        }

        func apply() {
            guard window != nil else { return }
            var responder: UIResponder? = self
            while let current = responder {
                if let sheet = (current as? UIViewController)?.sheetPresentationController {
                    let effect: UIVisualEffect? = isEnabled ? clearEffect : nil
                    if sheet.backgroundEffect !== effect {
                        sheet.backgroundEffect = effect
                    }
                    for detent in sheet.detents where detent.backgroundEffect !== effect {
                        detent.backgroundEffect = effect
                    }
                    return
                }
                responder = current.next
            }
        }
    }
}

/// Lays out a tab's content in side-strip mode: below the overlaid sheet
/// header, with a clear tab container, and clipped to the sheet body's rounded
/// bottom corners so wide rows never spill into the strip. No-op when disabled.
struct SideStripTabContentLayout: ViewModifier {
    var isEnabled: Bool
    var topInset: CGFloat
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        Group {
            if isEnabled {
                content
                    .padding(.top, topInset)
                    .mask {
                        UnevenRoundedRectangle(
                            bottomLeadingRadius: cornerRadius, bottomTrailingRadius: cornerRadius,
                            style: .continuous
                        )
                        .padding(.top, topInset)
                        .ignoresSafeArea(.container, edges: .bottom)
                    }
            } else {
                content
            }
        }
        .background(ClearTabContainerBackground(isEnabled: isEnabled))
    }
}

/// The tab bar controller behind a SwiftUI `TabView` and each tab's view
/// controller paint an opaque system background across the whole sheet,
/// including the side strip. Placed inside a tab's content, this clears both
/// so only the SwiftUI background (which respects the safe area) is drawn and
/// the native tab bar floats over the map in the strip.
struct ClearTabContainerBackground: UIViewRepresentable {
    var isEnabled: Bool

    func makeUIView(context: Context) -> ProbeView { ProbeView() }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.isEnabled = isEnabled
        uiView.apply()
    }

    final class ProbeView: UIView {
        var isEnabled = false
        private var hasCleared = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            apply()
        }

        func apply() {
            guard window != nil, isEnabled || hasCleared else { return }
            var responder: UIResponder? = self
            while let current = responder, !(current is UIViewController) {
                responder = current.next
            }
            guard let tabContent = responder as? UIViewController,
                  let tabBarController = tabContent.tabBarController else { return }
            let color: UIColor = isEnabled ? .clear : .systemBackground
            if tabContent.view.backgroundColor != color {
                tabContent.view.backgroundColor = color
            }
            if tabBarController.view.backgroundColor != color {
                tabBarController.view.backgroundColor = color
            }
            hasCleared = isEnabled
        }
    }
}
