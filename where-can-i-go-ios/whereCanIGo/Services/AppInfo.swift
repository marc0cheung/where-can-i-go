import Foundation
import UIKit

/// App metadata, public links and feedback helpers used by the About screens.
enum AppInfo {
    // TODO: Replace with the real support address before release.
    static let feedbackEmail = "feedback@example.com"

    static let instagramHandle = "wherecanigo_app"
    static let instagramURL = URL(string: "https://www.instagram.com/wherecanigo_app/")!
    static let repositoryURL = URL(string: "https://github.com/marc0cheung/where-can-i-go")!
    static let newIssueURL = URL(string: "https://github.com/marc0cheung/where-can-i-go/issues/new")!
    static let licenseURL = URL(string: "https://github.com/marc0cheung/where-can-i-go/blob/main/LICENSE")!
    static let privacyPolicyURL = URL(string: "https://github.com/marc0cheung/where-can-i-go/blob/main/PRIVACY.md")!

    static var displayName: String {
        Bundle.main.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
            ?? "Where Can I Go"
    }

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
    }

    /// Hardware identifier such as "iPhone17,1".
    static var deviceModel: String {
        var info = utsname()
        uname(&info)
        let identifier = withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }

    static var diagnostics: String {
        """
        App: \(version) (\(build))
        iOS: \(UIDevice.current.systemVersion)
        Device: \(deviceModel)
        Language: \(Locale.preferredLanguages.first ?? "–")
        """
    }

    static func feedbackMailURL() -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: String(localized: "feedback.mail.subject")),
            URLQueryItem(name: "body", value: "\n\n\n---\n\(diagnostics)"),
        ]
        return components.url
    }
}
