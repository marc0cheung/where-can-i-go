import SwiftUI
import UniformTypeIdentifiers

/// Friends segment of the Travels tab.
struct FriendsSection: View {
    @EnvironmentObject private var friendStore: FriendStore

    @State private var showShare = false
    @State private var showImporter = false
    @State private var pickedURL: URL?
    @State private var incoming: IncomingTravelCard?
    @State private var selectedFriend: Friend?
    @State private var pendingRemoval: Friend?
    @State private var errorMessage: String?
    @State private var errorTitle: LocalizedStringKey = "Couldn't Open Travel Card"

    var body: some View {
        VStack(spacing: 10) {
            actionButton("Share My Travel Card", systemImage: "square.and.arrow.up") {
                showShare = true
            }
            actionButton("Add Friend", systemImage: "person.badge.plus") {
                showImporter = true
            }
        }
        .cardListRow()
        .sheet(isPresented: $showShare) { ShareCardSheet() }
        .sheet(item: $incoming) { incoming in
            ReceiveCardSheet(incoming: incoming)
        }
        .sheet(item: $selectedFriend) { friend in
            FriendDetailSheet(friendID: friend.sharerID)
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.travelCard, .json]) { result in
            switch result {
            case .success(let url): pickedURL = url
            case .failure(let error):
                if let cocoaError = error as? CocoaError, cocoaError.code == .userCancelled { return }
                showError(error)
            }
        }
        .task(id: friendStore.incomingCardURL) {
            guard let url = friendStore.incomingCardURL else { return }
            await open(url)
            friendStore.incomingCardURL = nil
        }
        .task(id: pickedURL) {
            guard let url = pickedURL else { return }
            await open(url)
            pickedURL = nil
        }
        .confirmationDialog("Remove \(pendingRemoval?.name ?? "")?",
                            isPresented: Binding { pendingRemoval != nil } set: { if !$0 { pendingRemoval = nil } },
                            titleVisibility: .visible,
                            presenting: pendingRemoval) { friend in
            Button("Remove Friend", role: .destructive) {
                do {
                    try friendStore.remove(id: friend.sharerID)
                } catch {
                    errorTitle = "Couldn't Save"
                    errorMessage = error.localizedDescription
                }
            }
        } message: { _ in
            Text("This deletes their card from this device. Your friend isn't notified, and they keep any card you shared.")
        }
        .alert(errorTitle, isPresented: Binding {
            errorMessage != nil
        } set: { if !$0 { errorMessage = nil } }) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(verbatim: errorMessage ?? "")
        }

        if let loadError = friendStore.loadError {
            VStack(alignment: .leading, spacing: 8) {
                Label("Couldn't load friends", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(verbatim: loadError).font(.caption).foregroundStyle(.secondary)
                Button("Try Again") { friendStore.load() }
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .cardListRow()
        } else if friendStore.friends.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "person.2")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No friends yet")
                    .font(.subheadline.weight(.semibold))
                Text("Exchange travel cards with friends to see where they've been and where they want to go, even offline. Cards update only when a friend shares again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .cardListRow()
        } else {
            Text("Friends")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .cardListRow()

            ForEach(friendStore.sortedFriends) { friend in
                Button {
                    selectedFriend = friend
                } label: {
                    FriendRow(friend: friend)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        pendingRemoval = friend
                    } label: {
                        Image(systemName: "person.badge.minus")
                    }
                    .accessibilityLabel(Text("Remove Friend"))
                    .tint(.red)
                }
                .cardListRow()
            }
        }
    }

    private func actionButton(_ title: LocalizedStringKey, systemImage: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func open(_ url: URL) async {
        do {
            let card = try await TravelCardReader.read(from: url)
            let ownID = try? SharingIdentity.currentSharerID()
            incoming = IncomingTravelCard(card: card,
                                          receipt: friendStore.receipt(for: card, ownSharerID: ownID ?? nil))
        } catch {
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        errorTitle = "Couldn't Open Travel Card"
        errorMessage = error.localizedDescription
    }
}

struct FriendRow: View {
    let friend: Friend

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatar(photoData: friend.card.photo, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: friend.name)
                    .font(.subheadline.weight(.semibold))
                Text(TravelCardText.lastReceived(friend.lastReceivedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(minHeight: 56)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
