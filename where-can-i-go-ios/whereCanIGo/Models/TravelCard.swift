import Foundation
import CryptoKit
import UniformTypeIdentifiers

extension UTType {
    /// Declared in whereCanIGo-Info.plist as an exported type conforming to public.json.
    nonisolated static let travelCard = UTType(exportedAs: "com.marcocheung.whereCanIGo.travelcard", conformingTo: .json)
}

/// Signed file exchanged between friends. See tech_notes.md, "Friends".
///
/// The signature covers the exact `payload` bytes, so the payload JSON is
/// stored as base64 and decoded only after the signature checks out.
nonisolated struct TravelCardEnvelope: Codable, Sendable {
    static let formatIdentifier = "wherecanigo.travelcard"
    static let currentSchemaVersion = 1
    static let fileExtension = "wcigcard"
    static let maxFileByteCount = 4 * 1024 * 1024

    var format: String = formatIdentifier
    var schemaVersion: Int = currentSchemaVersion
    var publicKey: Data
    var payload: Data
    var signature: Data
}

/// Which details a category includes. With every option off, the category
/// carries country codes only.
nonisolated struct TravelCardFields: Codable, Equatable, Hashable, Sendable {
    var dates = false
    var length = false
    var location = false
    var purpose = false

    var isCountriesOnly: Bool { !dates && !length && !location && !purpose }
}

nonisolated struct TravelCardShared: Codable, Equatable, Sendable {
    var photo: Bool
    /// `nil` means the category is not shared.
    var been: TravelCardFields?
    var wishlist: TravelCardFields?
}

nonisolated struct TravelCardVisit: Codable, Equatable, Hashable, Sendable {
    var countryCode: String
    var startDate: String? = nil      // "yyyy-MM-dd"
    var endDate: String? = nil
    var days: Int? = nil
    var location: String? = nil
    var purpose: String? = nil        // VisitPurpose raw value
}

nonisolated struct TravelCardPlan: Codable, Equatable, Hashable, Sendable {
    var countryCode: String
    var startDate: String? = nil      // "yyyy-MM-dd"
    var endDate: String? = nil
    var days: Int? = nil
    var location: String? = nil
    var purpose: String? = nil        // VisitPurpose raw value
}

nonisolated struct TravelCardPayload: Codable, Equatable, Sendable {
    var sharerID: String
    var cardRevision: Int64
    var createdAt: String             // ISO 8601, see BackupTimestamp
    var displayName: String
    var photo: Data? = nil            // JPEG, base64 in JSON
    var been: [TravelCardVisit]? = nil
    var wishlist: [TravelCardPlan]? = nil
    var shared: TravelCardShared

    var createdDate: Date? { BackupTimestamp.date(from: createdAt) }
}

/// A card whose signature and contents have been checked.
nonisolated struct VerifiedTravelCard: Sendable {
    let publicKey: Data
    let payload: TravelCardPayload

    var sharerID: String { payload.sharerID }
}

nonisolated enum TravelCardLimits {
    static let displayNameLength = 60
    static let locationLength = 200
    static let beenCount = 5_000
    static let wishlistCount = 2_000
    static let maxDays = 36_500
    static let photoByteCount = 1024 * 1024
}

nonisolated enum TravelCardError: LocalizedError, Equatable, Sendable {
    case notATravelCard
    case unsupportedVersion(Int)
    case invalidSignature
    case invalidContent
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .notATravelCard:
            return String(localized: "This file isn't a travel card.")
        case .unsupportedVersion:
            return String(localized: "This travel card was made by a newer version of the app. Update the app and try again.")
        case .invalidSignature:
            return String(localized: "This travel card couldn't be verified. It may have been changed after it was shared.")
        case .invalidContent:
            return String(localized: "This travel card contains invalid data.")
        case .fileTooLarge:
            return String(localized: "This file is too large to be a travel card.")
        }
    }
}

// MARK: - Identity helpers

nonisolated enum TravelCardCrypto {
    static func sharerID(forPublicKey raw: Data) -> String {
        SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined()
    }

    /// Twelve digits derived from the public key, shown as three groups of four.
    static func safetyCode(forPublicKey raw: Data) -> String {
        let digest = Array(SHA256.hash(data: Data("wcig-safety".utf8) + raw))
        let value = digest.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) } % 1_000_000_000_000
        let digits = String(format: "%012llu", value)
        return stride(from: 0, to: 12, by: 4).map { start in
            let lower = digits.index(digits.startIndex, offsetBy: start)
            return String(digits[lower..<digits.index(lower, offsetBy: 4)])
        }.joined(separator: " ")
    }
}

// MARK: - Encoding and verification

nonisolated extension TravelCardEnvelope {
    static func make(payload: TravelCardPayload, signingKey: P256.Signing.PrivateKey) throws -> TravelCardEnvelope {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payloadData = try encoder.encode(payload)
        let signature = try signingKey.signature(for: payloadData)
        return TravelCardEnvelope(
            publicKey: signingKey.publicKey.rawRepresentation,
            payload: payloadData,
            signature: signature.rawRepresentation
        )
    }

    func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Reads `format` and `schemaVersion` first so other JSON files, including
    /// backups, are reported as "not a travel card".
    static func decodeAndVerify(_ data: Data) throws -> VerifiedTravelCard {
        guard data.count <= maxFileByteCount else { throw TravelCardError.fileTooLarge }
        struct Header: Decodable { var format: String?; var schemaVersion: Int? }
        guard let header = try? JSONDecoder().decode(Header.self, from: data),
              header.format == formatIdentifier else {
            throw TravelCardError.notATravelCard
        }
        guard let version = header.schemaVersion else { throw TravelCardError.notATravelCard }
        guard version <= currentSchemaVersion else { throw TravelCardError.unsupportedVersion(version) }
        guard let envelope = try? JSONDecoder().decode(TravelCardEnvelope.self, from: data) else {
            throw TravelCardError.invalidContent
        }
        guard let key = try? P256.Signing.PublicKey(rawRepresentation: envelope.publicKey),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: envelope.signature),
              key.isValidSignature(signature, for: envelope.payload) else {
            throw TravelCardError.invalidSignature
        }
        guard var payload = try? JSONDecoder().decode(TravelCardPayload.self, from: envelope.payload) else {
            throw TravelCardError.invalidContent
        }
        guard payload.sharerID == TravelCardCrypto.sharerID(forPublicKey: envelope.publicKey) else {
            throw TravelCardError.invalidSignature
        }
        try payload.validateAndNormalize()
        return VerifiedTravelCard(publicKey: envelope.publicKey, payload: payload)
    }
}

nonisolated extension TravelCardPayload {
    /// Checks limits and formats, drops data for categories marked as not
    /// shared, and re-encodes the photo (which also strips EXIF metadata).
    /// Cards restored from a backup were re-encoded when first received, so
    /// they pass `reencodePhoto: false` and only get the size check.
    mutating func validateAndNormalize(reencodePhoto: Bool = true) throws {
        displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty, displayName.count <= TravelCardLimits.displayNameLength,
              cardRevision > 0, createdDate != nil else {
            throw TravelCardError.invalidContent
        }

        if shared.been == nil { been = nil } else if been == nil { been = [] }
        if shared.wishlist == nil { wishlist = nil } else if wishlist == nil { wishlist = [] }
        guard (been?.count ?? 0) <= TravelCardLimits.beenCount,
              (wishlist?.count ?? 0) <= TravelCardLimits.wishlistCount else {
            throw TravelCardError.invalidContent
        }
        for visit in been ?? [] {
            try Self.validate(countryCode: visit.countryCode, start: visit.startDate, end: visit.endDate,
                              days: visit.days, location: visit.location)
        }
        for plan in wishlist ?? [] {
            try Self.validate(countryCode: plan.countryCode, start: plan.startDate, end: plan.endDate,
                              days: plan.days, location: plan.location)
        }

        if shared.photo, let data = photo {
            guard data.count <= TravelCardLimits.photoByteCount else { throw TravelCardError.invalidContent }
            if reencodePhoto {
                guard let prepared = try? UserProfileStore.preparePhoto(data) else {
                    throw TravelCardError.invalidContent
                }
                photo = prepared
            }
        } else {
            photo = nil
        }
    }

    private static func validate(countryCode: String, start: String?, end: String?,
                                 days: Int?, location: String?) throws {
        guard countryCode.count == 3,
              countryCode.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) }) else {
            throw TravelCardError.invalidContent
        }
        let startDate = try start.map { try BackupDay.date(from: $0) }
        let endDate = try end.map { try BackupDay.date(from: $0) }
        if let startDate, let endDate, endDate < startDate { throw TravelCardError.invalidContent }
        if let days, !(1...TravelCardLimits.maxDays).contains(days) { throw TravelCardError.invalidContent }
        if let location, location.count > TravelCardLimits.locationLength { throw TravelCardError.invalidContent }
    }
}

// MARK: - Display helpers

nonisolated extension TravelCardVisit {
    var purposeValue: VisitPurpose? {
        purpose.map { VisitPurpose(rawValue: $0) ?? .other }
    }

    var start: Date? { startDate.flatMap { try? BackupDay.date(from: $0) } }
    var end: Date? { endDate.flatMap { try? BackupDay.date(from: $0) } }

    var dayCount: Int? {
        if let days { return days }
        guard let start, let end else { return nil }
        return TravelCardDates.inclusiveDays(from: start, to: end)
    }
}

nonisolated extension TravelCardPlan {
    var purposeValue: VisitPurpose? {
        purpose.map { VisitPurpose(rawValue: $0) ?? .other }
    }

    var start: Date? { startDate.flatMap { try? BackupDay.date(from: $0) } }
    var end: Date? { endDate.flatMap { try? BackupDay.date(from: $0) } }

    var dayCount: Int? {
        if let days { return days }
        guard let start, let end else { return nil }
        return TravelCardDates.inclusiveDays(from: start, to: end)
    }
}

extension TravelCardPlan {
    /// Converts to a read-only `PlannedTrip` so `WishlistStats` can be reused.
    var plannedTrip: PlannedTrip {
        if start != nil || end != nil {
            return PlannedTrip(countryCode: countryCode, createdAt: .distantPast,
                               location: location, purpose: purposeValue ?? .other,
                               durationMode: .dates, startDate: start, endDate: end)
        }
        return PlannedTrip(countryCode: countryCode, createdAt: .distantPast,
                           location: location, purpose: purposeValue ?? .other,
                           durationMode: days == nil ? .notSet : .estimatedDays, estimatedDays: days)
    }
}

nonisolated enum TravelCardDates {
    static func inclusiveDays(from start: Date, to end: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                           to: calendar.startOfDay(for: end)).day ?? 0
        return max(0, days) + 1
    }
}
