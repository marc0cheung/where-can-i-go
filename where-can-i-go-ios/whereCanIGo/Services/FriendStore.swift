import Foundation
import Combine

/// A friend saved on this device: the last verified card plus local settings.
nonisolated struct Friend: Codable, Identifiable, Equatable, Sendable {
    var id: String { sharerID }
    let sharerID: String
    /// Raw P-256 public key, trusted on first use.
    var publicKey: Data
    var nickname: String?
    var addedAt: Date
    var lastReceivedAt: Date
    var card: TravelCardPayload

    var name: String {
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? card.displayName : trimmed
    }

    var safetyCode: String { TravelCardCrypto.safetyCode(forPublicKey: publicKey) }
}

/// Result of checking a received card against the saved friends.
enum TravelCardReceipt {
    case ownCard
    case new(sameName: [Friend])
    case update(existing: Friend)
    case unchanged(existing: Friend)
    case older(existing: Friend)
}

@MainActor
final class FriendStore: ObservableObject {
    @Published private(set) var friends: [Friend] = []
    @Published private(set) var loadError: String?
    /// A card file opened from outside the app, waiting for the Friends screen.
    @Published var incomingCardURL: URL?

    private let fileURL: URL

    private struct StoredFile: Codable {
        var schemaVersion = 1
        var friends: [Friend]
    }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? URL.documentsDirectory.appendingPathComponent("friends.json")
        load()
    }

    var sortedFriends: [Friend] {
        friends.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func friend(id: String) -> Friend? {
        friends.first { $0.sharerID == id }
    }

    func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            friends = try Self.decoder.decode(StoredFile.self, from: data).friends
            loadError = nil
        } catch CocoaError.fileReadNoSuchFile {
            friends = []
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: Receiving

    func receipt(for card: VerifiedTravelCard, ownSharerID: String?) -> TravelCardReceipt {
        if card.sharerID == ownSharerID { return .ownCard }
        if let existing = friend(id: card.sharerID) {
            if card.payload.cardRevision > existing.card.cardRevision { return .update(existing: existing) }
            if card.payload.cardRevision == existing.card.cardRevision { return .unchanged(existing: existing) }
            return .older(existing: existing)
        }
        let name = card.payload.displayName.lowercased()
        let sameName = friends.filter {
            $0.card.displayName.lowercased() == name || $0.name.lowercased() == name
        }
        return .new(sameName: sameName)
    }

    /// Saves the card as a new friend, or replaces the snapshot of an existing one.
    /// `replacing` moves an existing friend to the card's new identity and keeps
    /// the local nickname.
    @discardableResult
    func save(_ card: VerifiedTravelCard, replacing replacedID: String? = nil, now: Date = Date()) throws -> Friend {
        var updated = friends
        let previous = updated.first { $0.sharerID == card.sharerID }
            ?? replacedID.flatMap { id in updated.first { $0.sharerID == id } }
        if let existing = updated.first(where: { $0.sharerID == card.sharerID }) {
            guard existing.publicKey == card.publicKey,
                  card.payload.cardRevision > existing.card.cardRevision else {
                return existing
            }
        }
        updated.removeAll { $0.sharerID == card.sharerID || $0.sharerID == replacedID }
        // friends.json stores whole seconds, so the in-memory copy matches what reloads.
        let now = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down))
        let friend = Friend(
            sharerID: card.sharerID,
            publicKey: card.publicKey,
            nickname: previous?.nickname,
            addedAt: previous?.addedAt ?? now,
            lastReceivedAt: now,
            card: card.payload
        )
        updated.append(friend)
        try persist(updated)
        return friend
    }

    func setNickname(_ nickname: String?, for id: String) throws {
        guard let index = friends.firstIndex(where: { $0.sharerID == id }) else { return }
        var updated = friends
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        updated[index].nickname = trimmed?.isEmpty == false ? String(trimmed!.prefix(TravelCardLimits.displayNameLength)) : nil
        try persist(updated)
    }

    func remove(id: String) throws {
        try persist(friends.filter { $0.sharerID != id })
    }

    // MARK: Backup

    func snapshot() -> [Friend] { friends }

    func replaceAll(with newFriends: [Friend]) throws {
        try persist(newFriends)
    }

    /// Keeps the newer card for each friend; local nicknames on this device win.
    func merge(_ incoming: [Friend]) throws -> Int {
        var byID = Dictionary(friends.map { ($0.sharerID, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = 0
        for friend in incoming {
            if var existing = byID[friend.sharerID] {
                guard existing.publicKey == friend.publicKey,
                      friend.card.cardRevision > existing.card.cardRevision else { continue }
                existing.card = friend.card
                existing.lastReceivedAt = max(existing.lastReceivedAt, friend.lastReceivedAt)
                if existing.nickname == nil { existing.nickname = friend.nickname }
                byID[friend.sharerID] = existing
            } else {
                byID[friend.sharerID] = friend
            }
            changed += 1
        }
        if changed > 0 { try persist(Array(byID.values)) }
        return changed
    }

    // MARK: Persistence

    private func persist(_ newFriends: [Friend]) throws {
        let data = try Self.encoder.encode(StoredFile(friends: newFriends))
        try data.write(to: fileURL, options: .atomic)
        friends = newFriends
        loadError = nil
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - Reading card files

enum TravelCardReader {
    /// Reads and verifies a card from a file URL off the main thread.
    /// Files delivered to Documents/Inbox are removed after reading. Files
    /// opened in place from the Files app are left where they are.
    static func read(from url: URL) async throws -> VerifiedTravelCard {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
            if url.standardizedFileURL.path.hasPrefix(inboxURL.standardizedFileURL.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let task = Task.detached(priority: .userInitiated) { () throws -> VerifiedTravelCard in
            // Files opens cards in place. Coordinated reading downloads a card
            // that is still only in iCloud Drive.
            var coordinationError: NSError?
            var result: Result<Data, Error> = .failure(TravelCardError.notATravelCard)
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
                result = Result {
                    let values = try readURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    guard values.isRegularFile == true else { throw TravelCardError.notATravelCard }
                    guard (values.fileSize ?? 0) <= TravelCardEnvelope.maxFileByteCount else {
                        throw TravelCardError.fileTooLarge
                    }
                    return try Data(contentsOf: readURL)
                }
            }
            if let coordinationError { throw coordinationError }
            return try TravelCardEnvelope.decodeAndVerify(try result.get())
        }
        return try await task.value
    }

    private static var inboxURL: URL {
        URL.documentsDirectory.appendingPathComponent("Inbox", isDirectory: true)
    }
}
