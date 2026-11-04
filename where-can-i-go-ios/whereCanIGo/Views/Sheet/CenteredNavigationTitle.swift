import SwiftUI

extension View {
    /// Inline navigation title that stays centered between leading and trailing
    /// toolbar buttons, including on windows with an asymmetric safe area
    /// (e.g. the iPhone Duo outer display), where the system title drifts left.
    func centeredNavigationTitle(_ title: Text) -> some View {
        navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    title
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }

    func centeredNavigationTitle(_ title: LocalizedStringKey) -> some View {
        centeredNavigationTitle(Text(title))
    }

    func centeredNavigationTitle(verbatim title: String) -> some View {
        centeredNavigationTitle(Text(verbatim: title))
    }
}
