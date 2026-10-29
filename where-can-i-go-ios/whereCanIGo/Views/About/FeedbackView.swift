import SwiftUI
import UIKit

struct FeedbackView: View {
    @Environment(\.openURL) private var openURL
    @State private var showMailUnavailable = false

    var body: some View {
        Form {
            Section {
                Button(action: sendEmail) {
                    Label("Email Us", systemImage: "envelope")
                        .foregroundStyle(Color.primary)
                }
            } footer: {
                Text("feedback.email.footer")
            }

            Section {
                Link(destination: AppInfo.newIssueURL) {
                    Label("Open a GitHub Issue", systemImage: "exclamationmark.bubble")
                        .foregroundStyle(Color.primary)
                }
            } footer: {
                Text("feedback.github.footer")
            }
        }
        .navigationTitle("Send Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .alert("No Mail App Found", isPresented: $showMailUnavailable) {
            Button("Copy Email Address") {
                UIPasteboard.general.string = AppInfo.feedbackEmail
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please send your feedback to \(AppInfo.feedbackEmail).")
        }
    }

    private func sendEmail() {
        guard let url = AppInfo.feedbackMailURL() else {
            showMailUnavailable = true
            return
        }
        openURL(url) { accepted in
            if !accepted { showMailUnavailable = true }
        }
    }
}
