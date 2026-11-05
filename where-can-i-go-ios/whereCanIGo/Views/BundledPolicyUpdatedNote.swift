import SwiftUI

struct BundledPolicyUpdatedNote: View {
    enum Style {
        case footer
        case centered
        case leading
    }

    @EnvironmentObject private var appState: AppState
    var style: Style = .leading

    var body: some View {
        if let updatedAt = appState.bundledEntryPolicyUpdatedAt {
            let message = Text("Bundled entry policies last updated: \(formattedDate(updatedAt))")
            switch style {
            case .footer:
                message
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            case .centered:
                message
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            case .leading:
                message
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let locale = Locale.current.language.languageCode == .english ? Locale(identifier: "en_GB") : .current
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: .gmt))
    }
}
