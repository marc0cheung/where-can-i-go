import SwiftUI
import CryptoKit

/// Confirms what the next card contains, then opens the share sheet.
/// Used on its own (`ShareCardSheet`) and after receiving a friend's card.
struct ShareCardView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var profileStore: UserProfileStore

    var recipientName: String?
    let onFinish: () -> Void

    @State private var options = SharingOptions.load()
    @State private var rememberAsDefault = false
    @State private var sharedFile: SharedFile?
    @State private var errorMessage: String?

    private var displayName: String {
        options.resolvedDisplayName(profileName: profileStore.profile.name)
    }

    private var hasPhoto: Bool { profileStore.profile.photoData != nil }

    private var summary: TravelCardSummary {
        var payload = TravelCardPayload(
            sharerID: "", cardRevision: 1, createdAt: "", displayName: displayName,
            shared: TravelCardShared(photo: options.includePhoto,
                                     been: options.includeBeen ? options.beenFields : nil,
                                     wishlist: options.includeWishlist ? options.wishlistFields : nil))
        payload.photo = options.includePhoto ? profileStore.profile.photoData : nil
        payload.been = options.includeBeen ? [] : nil
        payload.wishlist = options.includeWishlist ? [] : nil
        var summary = TravelCardSummary(payload: payload)
        summary.beenCount = options.includeBeen ? appState.data.visits.count : nil
        summary.wishlistCount = options.includeWishlist ? appState.data.plannedTrips.count : nil
        return summary
    }

    var body: some View {
        Form {
            Section {
                TravelCardContentRows(summary: summary)
            } header: {
                Text("This Card Includes")
            } footer: {
                Text("Notes, passport details, My Visas and visa attachments stay on this device. Friends keep the copy they receive, and later changes reach them only when you share again.")
            }

            SharingOptionsSections(options: $options,
                                   profileName: profileStore.profile.name,
                                   hasProfilePhoto: hasPhoto)

            Section {
                Toggle("Remember as Default", isOn: $rememberAsDefault)
            }
        }
        .navigationTitle(recipientName.map { String(localized: "Share with \($0)") }
                         ?? String(localized: "Share My Travel Card"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Share") { share() }
                    .disabled(displayName.isEmpty || profileStore.loadFailed)
            }
        }
        .onAppear {
            if !hasPhoto { options.includePhoto = false }
        }
        .sheet(item: $sharedFile) { file in
            ActivityView(items: [file.url]) { completed in
                sharedFile = nil
                if completed { onFinish() }
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Couldn't Create Travel Card", isPresented: Binding {
            errorMessage != nil
        } set: { if !$0 { errorMessage = nil } }) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
    }

    private func share() {
        if rememberAsDefault { options.save() }
        do {
            let result = try TravelCardBuilder.makeFile(
                options: options, profile: profileStore.profile, data: appState.data)
            sharedFile = SharedFile(url: result.fileURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ShareCardSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ShareCardView(onFinish: { dismiss() })
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
    }
}

// MARK: - Sharing Settings

struct SharingSettingsView: View {
    @EnvironmentObject private var profileStore: UserProfileStore
    @State private var options = SharingOptions.load()
    @State private var safetyCode: String?
    @State private var identityError: String?
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                Text("These settings are the defaults for your next travel card. You can change them each time you share.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            SharingOptionsSections(options: $options,
                                   profileName: profileStore.profile.name,
                                   hasProfilePhoto: profileStore.profile.photoData != nil)

            Section {
                Label("Notes", systemImage: "note.text")
                Label("Passport", systemImage: "person.text.rectangle")
                Label("My Visas and Attachments", systemImage: "doc.on.doc")
            } header: {
                Text("Kept on This Device")
            }

            Section {
                if let code = safetyCode {
                    LabeledContent("Safety Code") {
                        Text(verbatim: code).monospacedDigit()
                    }
                    Button("Reset Safety Code", role: .destructive) { confirmReset = true }
                        .confirmationDialog("Reset your safety code?", isPresented: $confirmReset, titleVisibility: .visible) {
                            Button("Reset", role: .destructive) {
                                do {
                                    try SharingIdentity.reset()
                                    safetyCode = nil
                                    identityError = nil
                                } catch {
                                    identityError = error.localizedDescription
                                }
                            }
                        } message: {
                            Text("Your next travel card will come from a new identity, and friends will see you as a new person. This can't be undone.")
                        }
                } else if let identityError {
                    Text(verbatim: identityError).foregroundStyle(.secondary)
                } else {
                    Text("Your sharing identity is created the first time you share a card.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Sharing Identity")
            } footer: {
                Text("Friends can compare this code with the one shown on their device to confirm a card came from you. Your identity is kept in iCloud Keychain when it's turned on.")
            }
        }
        .navigationTitle("Sharing")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: options) { _, newValue in newValue.save() }
        .task {
            do {
                safetyCode = try SharingIdentity.currentKey().map {
                    TravelCardCrypto.safetyCode(forPublicKey: $0.publicKey.rawRepresentation)
                }
            } catch {
                identityError = error.localizedDescription
            }
        }
    }
}
