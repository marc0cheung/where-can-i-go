import SwiftUI

struct PrivacyPolicyView: View {
    /// Update this whenever the policy text changes, together with PRIVACY.md.
    static let lastUpdated = DateComponents(calendar: .init(identifier: .gregorian), year: 2026, month: 10, day: 30).date!

    var body: some View {
        DocumentView(
            intro: "privacy.intro",
            sections: [
                DocumentSection(title: "privacy.collect.title", body: "privacy.collect.body"),
                DocumentSection(title: "privacy.device.title", body: "privacy.device.body"),
                DocumentSection(title: "privacy.leave.title", body: "privacy.leave.body"),
                DocumentSection(title: "privacy.apple.title", body: "privacy.apple.body"),
                DocumentSection(title: "privacy.delete.title", body: "privacy.delete.body"),
                DocumentSection(title: "privacy.changes.title", body: "privacy.changes.body"),
                DocumentSection(title: "privacy.contact.title", body: "privacy.contact.body \(AppInfo.feedbackEmail)"),
            ],
            footer: Text("Last updated: \(Self.lastUpdated.formatted(date: .long, time: .omitted))")
        )
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
