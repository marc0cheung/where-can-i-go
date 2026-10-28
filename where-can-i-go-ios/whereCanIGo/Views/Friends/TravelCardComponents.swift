import SwiftUI
import UIKit

// MARK: - Sharing options form

/// Controls shared by Sharing Settings and the share confirmation.
struct SharingOptionsSections: View {
    @Binding var options: SharingOptions
    let profileName: String
    let hasProfilePhoto: Bool

    var body: some View {
        Section {
            TextField("Display Name", text: $options.displayName,
                      prompt: Text(profileName.isEmpty ? String(localized: "Nickname") : profileName))
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
            Toggle("Profile Photo", isOn: $options.includePhoto)
                .disabled(!hasProfilePhoto)
        } header: {
            Text("Profile")
        } footer: {
            Text(hasProfilePhoto
                 ? "Friends see this name on your card. Any nickname works."
                 : "Friends see this name on your card. Any nickname works. Add a profile photo to share it.")
        }

        Section {
            Toggle("Share Been Records", isOn: $options.includeBeen.animation())
            if options.includeBeen {
                Toggle("Dates", isOn: $options.beenFields.dates)
                Toggle("Length of Stay", isOn: $options.beenFields.length)
                Toggle("Location", isOn: $options.beenFields.location)
                Toggle("Purpose", isOn: $options.beenFields.purpose)
            }
        } header: {
            Text("Been")
        } footer: {
            if options.includeBeen {
                Text("With every detail off, only countries are shared.")
            }
        }

        Section {
            Toggle("Share Wishlist", isOn: $options.includeWishlist.animation())
            if options.includeWishlist {
                Toggle("Planned Dates", isOn: $options.wishlistFields.dates)
                Toggle("Estimated Days", isOn: $options.wishlistFields.length)
                Toggle("Location", isOn: $options.wishlistFields.location)
                Toggle("Purpose", isOn: $options.wishlistFields.purpose)
            }
        } header: {
            Text("Wishlist")
        } footer: {
            if options.includeWishlist && options.wishlistFields.dates {
                Text("Planned dates show friends when you may be away.")
            } else if options.includeWishlist {
                Text("With every detail off, only countries are shared.")
            }
        }
    }
}

// MARK: - Card contents

enum TravelCardText {
    static func fields(_ fields: TravelCardFields, wishlist: Bool) -> String {
        var parts = [String(localized: "Countries")]
        if fields.dates { parts.append(wishlist ? String(localized: "Planned Dates") : String(localized: "Dates")) }
        if fields.length { parts.append(wishlist ? String(localized: "Estimated Days") : String(localized: "Length of Stay")) }
        if fields.location { parts.append(String(localized: "Location")) }
        if fields.purpose { parts.append(String(localized: "Purpose")) }
        return ListFormatter.localizedString(byJoining: parts)
    }

    static func category(count: Int?, fields: TravelCardFields?, wishlist: Bool) -> String {
        guard let count, let fields else { return String(localized: "Not shared") }
        return "\(self.count(count, wishlist: wishlist)) · \(self.fields(fields, wishlist: wishlist))"
    }

    static func count(_ count: Int?, wishlist: Bool) -> String {
        guard let count else { return String(localized: "Not shared") }
        return wishlist ? String(localized: "\(count) trips planned") : String(localized: "\(count) trips")
    }

    static func lastReceived(_ date: Date) -> String {
        String(localized: "Last received \(date.formatted(.relative(presentation: .named)))")
    }
}

/// Rows describing what a card contains.
struct TravelCardContentRows: View {
    let summary: TravelCardSummary

    var body: some View {
        LabeledContent("Display Name") {
            Text(verbatim: summary.displayName.isEmpty ? "—" : summary.displayName)
        }
        LabeledContent("Profile Photo",
                       value: summary.photoShared && summary.hasPhoto
                       ? String(localized: "Included") : String(localized: "Not shared"))
        LabeledContent("Been") {
            Text(TravelCardText.category(count: summary.beenCount, fields: summary.beenFields, wishlist: false))
                .multilineTextAlignment(.trailing)
        }
        LabeledContent("Wishlist") {
            Text(TravelCardText.category(count: summary.wishlistCount, fields: summary.wishlistFields, wishlist: true))
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Avatar, name and secondary lines, used at the top of friend sheets.
struct FriendHeader: View {
    let photoData: Data?
    let title: String
    let subtitle: String?
    var caption: String?

    var body: some View {
        HStack(spacing: 14) {
            ProfileAvatar(photoData: photoData, size: 60)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title).font(.title3.bold())
                if let subtitle {
                    Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary)
                }
                if let caption {
                    Text(verbatim: caption).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - System share sheet

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    let onComplete: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in onComplete(completed) }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}
