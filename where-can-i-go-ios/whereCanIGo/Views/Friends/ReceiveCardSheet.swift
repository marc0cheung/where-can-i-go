import SwiftUI

struct IncomingTravelCard: Identifiable {
    let id = UUID()
    let card: VerifiedTravelCard
    let receipt: TravelCardReceipt
}

/// Shows a received card, saves it, then offers to share the user's own card back.
struct ReceiveCardSheet: View {
    @EnvironmentObject private var friendStore: FriendStore
    @Environment(\.dismiss) private var dismiss

    let incoming: IncomingTravelCard

    @State private var savedFriend: Friend?
    @State private var wasUpdate = false
    @State private var showShare = false
    @State private var replaceCandidate: Friend?
    @State private var errorMessage: String?

    private var card: VerifiedTravelCard { incoming.card }
    private var payload: TravelCardPayload { card.payload }
    private var safetyCode: String { TravelCardCrypto.safetyCode(forPublicKey: card.publicKey) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FriendHeader(
                        photoData: payload.photo,
                        title: payload.displayName,
                        subtitle: String(localized: "Safety code \(safetyCode)"),
                        caption: payload.createdDate.map {
                            String(localized: "Created \($0.formatted(date: .abbreviated, time: .shortened))")
                        })
                }

                if let savedFriend {
                    shareBackSections(savedFriend)
                } else {
                    receiptSections
                }
            }
            .navigationTitle("Travel Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showShare) {
                ShareCardView(recipientName: savedFriend?.name, onFinish: { dismiss() })
            }
            .confirmationDialog(
                "Replace \(replaceCandidate?.name ?? "")?",
                isPresented: Binding { replaceCandidate != nil } set: { if !$0 { replaceCandidate = nil } },
                titleVisibility: .visible,
                presenting: replaceCandidate
            ) { friend in
                Button("Replace \(friend.name)", role: .destructive) {
                    save(replacing: friend.sharerID)
                }
            } message: { friend in
                Text("Future cards from \(friend.name) are accepted only from this new identity. Ask \(friend.name) to confirm that the safety code in their Sharing settings is \(safetyCode).")
            }
            .alert("Couldn't Save", isPresented: Binding {
                errorMessage != nil
            } set: { if !$0 { errorMessage = nil } }) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(verbatim: errorMessage ?? "")
            }
        }
    }

    // MARK: Before saving

    @ViewBuilder
    private var receiptSections: some View {
        switch incoming.receipt {
        case .ownCard:
            Section {
                Text("This is your own travel card.")
            }

        case .unchanged(let existing):
            Section {
                Text("You already have this card from \(existing.name).")
            }
            Section {
                Button("Share My Travel Card") {
                    savedFriend = existing
                    showShare = true
                }
            }

        case .older(let existing):
            Section {
                Text("You already have a newer card from \(existing.name), received \(existing.lastReceivedAt.formatted(.relative(presentation: .named))). This card wasn't saved.")
            }

        case .update(let existing):
            Section {
                changeRow("Display Name",
                          old: existing.card.displayName, new: payload.displayName)
                changeRow("Profile Photo",
                          old: photoText(existing.card), new: photoText(payload))
                changeRow("Been",
                          old: TravelCardText.count(existing.card.been?.count, wishlist: false),
                          new: TravelCardText.count(payload.been?.count, wishlist: false))
                changeRow("Wishlist",
                          old: TravelCardText.count(existing.card.wishlist?.count, wishlist: true),
                          new: TravelCardText.count(payload.wishlist?.count, wishlist: true))
            } header: {
                Text("Update \(existing.name)")
            } footer: {
                Text("The new card replaces the one you received \(existing.lastReceivedAt.formatted(.relative(presentation: .named))). Your nickname for this friend stays the same.")
            }
            Section {
                Button("Update Friend") { save() }
                    .bold()
            }

        case .new(let sameName):
            Section {
                TravelCardContentRows(summary: TravelCardSummary(payload: payload))
            } header: {
                Text("This Card Includes")
            }
            if sameName.isEmpty {
                Section {
                    Button("Add Friend") { save() }
                        .bold()
                }
            } else {
                Section {
                    Button("Add as New Friend") { save() }
                    ForEach(sameName) { friend in
                        Button("Replace \(friend.name)") { replaceCandidate = friend }
                    }
                } footer: {
                    Text("You already have a friend with this name. This card comes from a different sharing identity, such as a new phone or a different person. Replace the existing friend only after comparing safety codes.")
                }
            }
        }
    }

    private func changeRow(_ title: LocalizedStringKey, old: String, new: String) -> some View {
        LabeledContent(title) {
            if old == new {
                Text(verbatim: new)
            } else {
                Text(verbatim: "\(old) → \(new)")
                    .foregroundStyle(.tint)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func photoText(_ payload: TravelCardPayload) -> String {
        payload.photo == nil ? String(localized: "Not shared") : String(localized: "Included")
    }

    // MARK: After saving

    @ViewBuilder
    private func shareBackSections(_ friend: Friend) -> some View {
        Section {
            Label(wasUpdate ? "Updated \(friend.name)" : "Added \(friend.name)",
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
        Section {
            Button("Share My Travel Card") { showShare = true }
                .bold()
            Button("Not Now") { dismiss() }
        } header: {
            Text("Share your travel card with \(friend.name)?")
        } footer: {
            Text("\(friend.name) can add you after receiving your card.")
        }
    }

    private func save(replacing replacedID: String? = nil) {
        if case .update = incoming.receipt { wasUpdate = true }
        if replacedID != nil { wasUpdate = true }
        do {
            let friend = try friendStore.save(card, replacing: replacedID)
            withAnimation { savedFriend = friend }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
