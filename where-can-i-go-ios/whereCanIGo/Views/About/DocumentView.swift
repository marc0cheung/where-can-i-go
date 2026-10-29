import SwiftUI

/// A heading followed by a paragraph. The body supports Markdown via `LocalizedStringKey`.
struct DocumentSection: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let body: LocalizedStringKey
}

/// Scrollable long-form text page used by the privacy policy.
struct DocumentView: View {
    let intro: LocalizedStringKey?
    let sections: [DocumentSection]
    var footer: Text?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let intro {
                    Text(intro)
                        .font(.body)
                }
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title)
                            .font(.headline)
                        Text(section.body)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                if let footer {
                    footer
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 600, alignment: .leading)
            .padding()
            .frame(maxWidth: .infinity)
            .textSelection(.enabled)
        }
    }
}
