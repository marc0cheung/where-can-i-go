import Foundation
import CryptoKit

/// Defaults for the next travel card. Stored in UserDefaults; every option
/// starts off.
struct SharingOptions: Codable, Equatable {
    var displayName = ""
    var includePhoto = false
    var includeBeen = false
    var beenFields = TravelCardFields()
    var includeWishlist = false
    var wishlistFields = TravelCardFields()

    private static let storageKey = "sharing.defaults"

    static func load(from defaults: UserDefaults = .standard) -> SharingOptions {
        guard let data = defaults.data(forKey: storageKey),
              let options = try? JSONDecoder().decode(SharingOptions.self, from: data) else {
            return SharingOptions()
        }
        return options
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    /// Display name for the card: the sharing name if set, otherwise the profile name.
    func resolvedDisplayName(profileName: String) -> String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((name.isEmpty ? fallback : name).prefix(TravelCardLimits.displayNameLength))
    }
}

/// Builds and signs travel cards from the user's own data.
enum TravelCardBuilder {
    struct Result {
        let fileURL: URL
        let summary: TravelCardSummary
    }

    static func payload(options: SharingOptions, profile: UserProfile, data: AppData,
                        sharerID: String, revision: Int64, now: Date = Date()) throws -> TravelCardPayload {
        let photo: Data? = options.includePhoto
            ? try profile.photoData.map { try UserProfileStore.preparePhoto($0) }
            : nil
        let been: [TravelCardVisit]? = options.includeBeen
            ? data.visits.map { visit(from: $0, fields: options.beenFields) }
            : nil
        let wishlist: [TravelCardPlan]? = options.includeWishlist
            ? data.plannedTrips.map { plan(from: $0, fields: options.wishlistFields) }
            : nil
        return TravelCardPayload(
            sharerID: sharerID,
            cardRevision: revision,
            createdAt: BackupTimestamp.string(from: now),
            displayName: options.resolvedDisplayName(profileName: profile.name),
            photo: photo,
            been: been,
            wishlist: wishlist,
            shared: TravelCardShared(
                photo: options.includePhoto,
                been: options.includeBeen ? options.beenFields : nil,
                wishlist: options.includeWishlist ? options.wishlistFields : nil)
        )
    }

    /// Signs a new card and writes it to a temporary file for the share sheet.
    static func makeFile(options: SharingOptions, profile: UserProfile, data: AppData) throws -> Result {
        let key = try SharingIdentity.loadOrCreateKey()
        let sharerID = TravelCardCrypto.sharerID(forPublicKey: key.publicKey.rawRepresentation)
        let payload = try payload(options: options, profile: profile, data: data,
                                  sharerID: sharerID, revision: try SharingIdentity.nextRevision())
        let envelope = try TravelCardEnvelope.make(payload: payload, signingKey: key)

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TravelCards", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        let unique = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: unique, withIntermediateDirectories: true)
        let url = unique.appendingPathComponent(fileName(for: payload.displayName))
        try envelope.encodedData().write(to: url, options: .atomic)
        return Result(fileURL: url, summary: TravelCardSummary(payload: payload))
    }

    static func fileName(for displayName: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:").union(.newlines).union(.controlCharacters)
        let cleaned = displayName.components(separatedBy: invalid).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleaned.isEmpty ? "Travel Card" : cleaned
        return "\(base).\(TravelCardEnvelope.fileExtension)"
    }

    private static func visit(from visit: Visit, fields: TravelCardFields) -> TravelCardVisit {
        TravelCardVisit(
            countryCode: visit.countryCode,
            startDate: fields.dates ? visit.startDate.map(BackupDay.string(from:)) : nil,
            endDate: fields.dates ? visit.endDate.map(BackupDay.string(from:)) : nil,
            days: fields.length ? visit.dayCount : nil,
            location: fields.location ? visit.location : nil,
            purpose: fields.purpose ? visit.purpose.rawValue : nil
        )
    }

    private static func plan(from trip: PlannedTrip, fields: TravelCardFields) -> TravelCardPlan {
        let hasDates = trip.durationMode == .dates
        return TravelCardPlan(
            countryCode: trip.countryCode,
            startDate: fields.dates && hasDates ? trip.startDate.map(BackupDay.string(from:)) : nil,
            endDate: fields.dates && hasDates ? trip.endDate.map(BackupDay.string(from:)) : nil,
            days: fields.length ? trip.plannedDayCount : nil,
            location: fields.location ? trip.location : nil,
            purpose: fields.purpose ? trip.purpose.rawValue : nil
        )
    }
}

/// What a card contains, for confirmation and change summaries.
struct TravelCardSummary: Equatable {
    var displayName: String
    var hasPhoto: Bool
    var photoShared: Bool
    var beenCount: Int?
    var beenFields: TravelCardFields?
    var wishlistCount: Int?
    var wishlistFields: TravelCardFields?

    init(payload: TravelCardPayload) {
        displayName = payload.displayName
        hasPhoto = payload.photo != nil
        photoShared = payload.shared.photo
        beenCount = payload.been?.count
        beenFields = payload.shared.been
        wishlistCount = payload.wishlist?.count
        wishlistFields = payload.shared.wishlist
    }
}
