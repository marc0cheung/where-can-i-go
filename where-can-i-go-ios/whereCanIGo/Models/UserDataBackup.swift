import Foundation
import CryptoKit
import UniformTypeIdentifiers

// MARK: - Root document

/// Portable, versioned backup file. It has its own record types, separate from the persisted
/// `AppData` format, so internal models can change without breaking exported files.
///
/// Compatibility rules:
/// - Additive changes (new optional fields, new enum values) keep `schemaVersion`;
///   older apps ignore unknown keys and fall back on unknown enum values.
/// - Breaking changes bump `schemaVersion`; older apps reject newer versions.
/// - A missing optional section means the section was left out of the file.
///   An empty array means the user has no records of that type.
nonisolated struct UserDataBackup: Codable, Sendable {
    static let formatIdentifier = "wherecanigo.backup"
    static let currentSchemaVersion = 1
    static let maxFileByteCount = 100 * 1024 * 1024

    var format: String = UserDataBackup.formatIdentifier
    var schemaVersion: Int = UserDataBackup.currentSchemaVersion
    var kind: Kind = .fullBackup
    var exportedAt: Date = Date()
    var app: AppInfo? = nil
    var profile: Profile? = nil
    var passport: Passport? = nil
    var entryPolicies: EntryPolicies? = nil
    var personalVisas: [PersonalVisaRecord] = []
    var visits: [VisitRecord] = []
    var wishlist: [WishlistRecord] = []

    enum CodingKeys: String, CodingKey {
        case format, schemaVersion, kind, exportedAt, app, profile, passport,
             entryPolicies, personalVisas, visits, wishlist
    }
}

nonisolated extension UserDataBackup {
    /// Open-ended kind so unknown future values still decode (and are rejected gracefully).
    nonisolated struct Kind: RawRepresentable, Codable, Hashable, Sendable {
        let rawValue: String
        init(rawValue: String) { self.rawValue = rawValue }

        static let fullBackup = Kind(rawValue: "fullBackup")
        /// Reserved for the planned Friends feature (see tech_notes.md).
        static let visitShare = Kind(rawValue: "visitShare")
    }

    nonisolated struct AppInfo: Codable, Sendable {
        var version: String?
        var build: String?
        var platform: String?

        static var current: AppInfo {
            let info = Bundle.main.infoDictionary
            return AppInfo(version: info?["CFBundleShortVersionString"] as? String,
                           build: info?["CFBundleVersion"] as? String,
                           platform: "iOS")
        }
    }

    nonisolated struct Profile: Codable, Sendable {
        var displayName: String?
        /// nil = photo not included in this file.
        var photo: BackupMedia?
    }

    nonisolated struct Passport: Codable, Sendable {
        var code: String
    }

    /// Only the user's edits relative to the bundled defaults for `passport.code`.
    nonisolated struct EntryPolicies: Codable, Sendable {
        var overrides: [EntryPolicyRecord] = []
        var removedCountryCodes: [String] = []

        enum CodingKeys: String, CodingKey { case overrides, removedCountryCodes }
    }

    // Tolerant decoding: missing arrays/sections default to empty.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(String.self, forKey: .format)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .fullBackup
        exportedAt = try c.decodeIfPresent(Date.self, forKey: .exportedAt) ?? .distantPast
        app = try c.decodeIfPresent(AppInfo.self, forKey: .app)
        profile = try c.decodeIfPresent(Profile.self, forKey: .profile)
        passport = try c.decodeIfPresent(Passport.self, forKey: .passport)
        entryPolicies = try c.decodeIfPresent(EntryPolicies.self, forKey: .entryPolicies)
        personalVisas = try c.decodeIfPresent([PersonalVisaRecord].self, forKey: .personalVisas) ?? []
        visits = try c.decodeIfPresent([VisitRecord].self, forKey: .visits) ?? []
        wishlist = try c.decodeIfPresent([WishlistRecord].self, forKey: .wishlist) ?? []
    }
}

nonisolated extension UserDataBackup.EntryPolicies {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        overrides = try c.decodeIfPresent([EntryPolicyRecord].self, forKey: .overrides) ?? []
        removedCountryCodes = try c.decodeIfPresent([String].self, forKey: .removedCountryCodes) ?? []
    }
}

@MainActor extension UserDataBackup.EntryPolicies {
    /// The user's edits compared with the bundled defaults.
    static func diff(current: [DefaultVisaEntry], bundled: [DefaultVisaEntry]) -> Self {
        let bundledByCode = Dictionary(bundled.map { ($0.countryCode, $0) }, uniquingKeysWith: { _, last in last })
        let currentCodes = Set(current.map(\.countryCode))
        let overrides = current
            .filter { bundledByCode[$0.countryCode] != $0 }
            .sorted { $0.countryCode < $1.countryCode }
            .map { EntryPolicyRecord($0) }
        let removed = bundledByCode.keys.filter { !currentCodes.contains($0) }.sorted()
        return Self(overrides: overrides, removedCountryCodes: removed)
    }

    /// Bundled defaults, minus removals, with overrides applied.
    /// Overrides with a category unknown to this app version are skipped (bundled entry kept).
    func applied(to bundled: [DefaultVisaEntry]) -> (entries: [DefaultVisaEntry], skipped: Int) {
        let removed = Set(removedCountryCodes)
        var overridesByCode: [String: DefaultVisaEntry] = [:]
        var skipped = 0
        for record in overrides {
            if let entry = record.toModel() { overridesByCode[entry.countryCode] = entry } else { skipped += 1 }
        }
        var result = bundled.filter { !removed.contains($0.countryCode) && overridesByCode[$0.countryCode] == nil }
        result.append(contentsOf: overridesByCode.values.sorted { $0.countryCode < $1.countryCode })
        return (result, skipped)
    }
}

// MARK: - Lenient enum mapping (forward compatibility)

/// Main-actor because the app's enums (VisaCoverage, VisitPurpose, ...) are main-actor isolated.
@MainActor enum BackupValue {
    /// Missing → `missing`; unknown value (e.g. written by a newer app) → `unknown`.
    static func decode<T: RawRepresentable>(_ raw: String?, missing: T, unknown: T) -> T where T.RawValue == String {
        guard let raw else { return missing }
        return T(rawValue: raw) ?? unknown
    }
}

// MARK: - Records (DTOs: nonisolated; model mapping: @MainActor)

/// Maps to `DefaultVisaEntry`. Independent from its legacy Codable (duration/remark splitting).
nonisolated struct EntryPolicyRecord: Codable, Equatable, Sendable {
    var countryCode: String
    var category: String          // VisaCategory raw value, e.g. "visa_free"
    var duration: String? = nil
    var remark: String? = nil
}

@MainActor extension EntryPolicyRecord {
    init(_ entry: DefaultVisaEntry) {
        self.init(countryCode: entry.countryCode, category: entry.category.rawValue,
                  duration: entry.duration, remark: entry.remark)
    }

    /// nil = category unknown to this app version.
    func toModel() -> DefaultVisaEntry? {
        guard let category = VisaCategory(rawValue: category) else { return nil }
        return DefaultVisaEntry(countryCode: countryCode, category: category, duration: duration, remark: remark)
    }
}

nonisolated struct PersonalVisaRecord: Codable, Sendable {
    var id: UUID
    var countryCode: String
    var visaType: String
    var duration: String
    var expiryDate: String            // "yyyy-MM-dd"
    var effectiveDate: String? = nil  // "yyyy-MM-dd"
    var notes: String? = nil
    var coverage: String? = nil       // VisaCoverage raw value
    /// nil = attachments not included in this file; [] = visa has no attachments.
    var attachments: [BackupMedia]? = nil
}

@MainActor extension PersonalVisaRecord {
    init(_ visa: PersonalVisa, attachments: [BackupMedia]?) {
        self.init(id: visa.id,
                  countryCode: visa.countryCode,
                  visaType: visa.visaType,
                  duration: visa.duration,
                  expiryDate: BackupDay.string(from: visa.expiryDate),
                  effectiveDate: visa.effectiveDate.map { BackupDay.string(from: $0) },
                  notes: visa.notes,
                  coverage: visa.coverage.rawValue,
                  attachments: attachments)
    }

    func toModel(attachmentFileNames: [String]) throws -> PersonalVisa {
        try UserDataBackup.requireCountryCode(countryCode)
        return PersonalVisa(id: id,
                            countryCode: countryCode,
                            visaType: visaType,
                            duration: duration,
                            expiryDate: try BackupDay.date(from: expiryDate),
                            effectiveDate: try effectiveDate.map { try BackupDay.date(from: $0) },
                            notes: notes,
                            attachmentFileNames: attachmentFileNames,
                            coverage: BackupValue.decode(coverage, missing: VisaCoverage.issuingCountry,
                                                         unknown: .issuingCountry))
    }
}

nonisolated struct VisitRecord: Codable, Sendable {
    var id: UUID
    var countryCode: String
    var startDate: String? = nil      // "yyyy-MM-dd"
    var endDate: String? = nil
    var purpose: String? = nil        // VisitPurpose raw value
    var location: String? = nil
    var notes: String? = nil
}

@MainActor extension VisitRecord {
    init(_ visit: Visit) {
        self.init(id: visit.id,
                  countryCode: visit.countryCode,
                  startDate: visit.startDate.map { BackupDay.string(from: $0) },
                  endDate: visit.endDate.map { BackupDay.string(from: $0) },
                  purpose: visit.purpose.rawValue,
                  location: visit.location,
                  notes: visit.notes)
    }

    func toModel() throws -> Visit {
        try UserDataBackup.requireCountryCode(countryCode)
        return Visit(id: id,
                     countryCode: countryCode,
                     startDate: try startDate.map { try BackupDay.date(from: $0) },
                     endDate: try endDate.map { try BackupDay.date(from: $0) },
                     purpose: BackupValue.decode(purpose, missing: VisitPurpose.leisure, unknown: .other),
                     location: location,
                     notes: notes)
    }
}

/// Maps to `PlannedTrip`.
nonisolated struct WishlistRecord: Codable, Sendable {
    var id: UUID
    var countryCode: String
    var createdAt: Date
    var location: String? = nil
    var purpose: String? = nil        // VisitPurpose raw value
    var notes: String? = nil
    var durationMode: String? = nil   // PlannedDurationMode raw value
    var estimatedDays: Int? = nil
    var startDate: String? = nil      // "yyyy-MM-dd"
    var endDate: String? = nil
}

@MainActor extension WishlistRecord {
    init(_ trip: PlannedTrip) {
        self.init(id: trip.id,
                  countryCode: trip.countryCode,
                  createdAt: trip.createdAt,
                  location: trip.location,
                  purpose: trip.purpose.rawValue,
                  notes: trip.notes,
                  durationMode: trip.durationMode.rawValue,
                  estimatedDays: trip.estimatedDays,
                  startDate: trip.startDate.map { BackupDay.string(from: $0) },
                  endDate: trip.endDate.map { BackupDay.string(from: $0) })
    }

    func toModel() throws -> PlannedTrip {
        try UserDataBackup.requireCountryCode(countryCode)
        return PlannedTrip(id: id,
                           countryCode: countryCode,
                           createdAt: createdAt,
                           location: location,
                           purpose: BackupValue.decode(purpose, missing: VisitPurpose.leisure, unknown: .other),
                           notes: notes,
                           durationMode: BackupValue.decode(durationMode, missing: PlannedDurationMode.notSet,
                                                            unknown: .notSet),
                           estimatedDays: estimatedDays,
                           startDate: try startDate.map { try BackupDay.date(from: $0) },
                           endDate: try endDate.map { try BackupDay.date(from: $0) })
    }
}

// MARK: - Media

/// Single place to extend supported file types. Adding a type here needs no JSON format change.
nonisolated enum BackupMediaPolicy {
    /// e.g. add `.movie` later to support video attachments.
    static let attachmentTypes: [UTType] = [.image, .pdf]
    static let profilePhotoTypes: [UTType] = [.image]

    static let maxAttachmentByteCount = 20 * 1024 * 1024
    static let maxProfilePhotoByteCount = 10 * 1024 * 1024

    static func type(forFileName name: String) -> UTType? {
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? nil : UTType(filenameExtension: ext)
    }

    static func mimeType(forFileName name: String) -> String {
        type(forFileName: name)?.preferredMIMEType ?? "application/octet-stream"
    }

    static func isSupported(fileName: String, byteCount: Int, purpose: BackupMedia.Purpose) -> Bool {
        guard let type = type(forFileName: fileName) else { return false }
        let (allowed, limit) = purpose == .attachment
            ? (attachmentTypes, maxAttachmentByteCount)
            : (profilePhotoTypes, maxProfilePhotoByteCount)
        return byteCount <= limit && allowed.contains { type.conforms(to: $0) }
    }
}

/// Raw file read from disk, before packing into the backup.
nonisolated struct BackupFile: Sendable {
    var fileName: String
    var data: Data
}

nonisolated struct BackupMedia: Codable, Equatable, Sendable {
    nonisolated enum Purpose: Sendable { case attachment, profilePhoto }

    var fileName: String
    /// Informational only; the app derives the type from `fileName`'s extension.
    var mimeType: String
    var byteCount: Int
    var sha256: String
    var data: Data                    // base64 in JSON

    init(fileName: String, data: Data) {
        self.fileName = fileName
        self.mimeType = BackupMediaPolicy.mimeType(forFileName: fileName)
        self.byteCount = data.count
        self.sha256 = Self.sha256Hex(data)
        self.data = data
    }

    /// nil = this app version can't include the file (unsafe name, unsupported type, too large).
    static func forExport(_ file: BackupFile, purpose: Purpose) -> BackupMedia? {
        guard isSafeFileName(file.fileName), !file.data.isEmpty,
              BackupMediaPolicy.isSupported(fileName: file.fileName, byteCount: file.data.count, purpose: purpose)
        else { return nil }
        return BackupMedia(fileName: file.fileName, data: file.data)
    }

    /// Cheap checks: safe file name and declared size.
    func validateStructure() throws {
        guard Self.isSafeFileName(fileName), byteCount > 0, data.count == byteCount else {
            throw UserDataBackupError.invalidAttachment(fileName)
        }
    }

    /// Full check including checksum. Tampered/corrupted → throws and the whole import is rejected.
    func validateIntegrity() throws {
        try validateStructure()
        guard Self.sha256Hex(data) == sha256.lowercased() else {
            throw UserDataBackupError.invalidAttachment(fileName)
        }
    }

    /// Intact but not usable by this app version → skipped, import continues.
    func isSupported(for purpose: Purpose) -> Bool {
        BackupMediaPolicy.isSupported(fileName: fileName, byteCount: byteCount, purpose: purpose)
    }

    static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 255
            && !name.hasPrefix(".")
            && !name.contains("/") && !name.contains("\\") && !name.contains("..")
            && name.rangeOfCharacter(from: .controlCharacters) == nil
            && (name as NSString).lastPathComponent == name
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Date helpers

/// Calendar-day fields ("yyyy-MM-dd"), Gregorian, in the device's current time zone,
/// so a trip on 1 April stays on 1 April after moving to a phone in another time zone.
nonisolated enum BackupDay {
    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }

    static func string(from date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(from value: String) throws -> Date {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              string(from: date) == value          // rejects e.g. 2026-02-30
        else { throw UserDataBackupError.invalidDate(value) }
        return date                                 // already start of day
    }
}

/// Exact instants (createdAt, exportedAt), UTC with milliseconds.
nonisolated enum BackupTimestamp {
    private static func formatter(fractional: Bool) -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return f
    }

    static func string(from date: Date) -> String {
        formatter(fractional: true).string(from: date)
    }

    static func date(from value: String) -> Date? {
        formatter(fractional: true).date(from: value) ?? formatter(fractional: false).date(from: value)
    }
}

// MARK: - Errors

nonisolated enum UserDataBackupError: LocalizedError, Equatable, Sendable {
    case notABackupFile
    case corrupted
    case fileTooLarge
    case unsupportedVersion(Int)
    case unsupportedKind(String)
    case invalidCountryCode(String)
    case duplicateRecord(String)
    case invalidDate(String)
    case invalidAttachment(String)

    var errorDescription: String? {
        switch self {
        case .notABackupFile:             return String(localized: "backup.error.notABackup")
        case .corrupted:                  return String(localized: "backup.error.corrupted")
        case .fileTooLarge:               return String(localized: "backup.error.fileTooLarge")
        case .unsupportedVersion(let v):  return String(localized: "backup.error.unsupportedVersion \(v)")
        case .unsupportedKind(let k):     return String(localized: "backup.error.unsupportedKind \(k)")
        case .invalidCountryCode(let c):  return String(localized: "backup.error.invalidCountryCode \(c)")
        case .duplicateRecord:            return String(localized: "backup.error.duplicateRecord")
        case .invalidDate(let d):         return String(localized: "backup.error.invalidDate \(d)")
        case .invalidAttachment(let n):   return String(localized: "backup.error.invalidAttachment \(n)")
        }
    }
}

// MARK: - Encode / decode (background-safe)

nonisolated extension UserDataBackup {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(BackupTimestamp.string(from: date))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = BackupTimestamp.date(from: raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid timestamp: \(raw)")
            }
            return date
        }
        return decoder
    }

    func encodedData() throws -> Data {
        try Self.makeEncoder().encode(self)
    }

    /// Background-safe: header → version → JSON decode → media checksums.
    /// Leaves app models untouched. Call `validate(checkMediaChecksums: false)` on the main actor afterwards.
    static func decodeVerifyingMedia(from data: Data) throws -> UserDataBackup {
        guard data.count <= maxFileByteCount else { throw UserDataBackupError.fileTooLarge }

        guard let header = try? JSONDecoder().decode(BackupHeader.self, from: data),
              header.format == formatIdentifier,
              let version = header.schemaVersion, version >= 1 else {
            throw UserDataBackupError.notABackupFile
        }
        guard version <= currentSchemaVersion else {
            throw UserDataBackupError.unsupportedVersion(version)
        }

        let backup: UserDataBackup
        do { backup = try makeDecoder().decode(UserDataBackup.self, from: data) }
        catch { throw UserDataBackupError.corrupted }

        // Expensive part (SHA-256) stays off the main thread.
        for record in backup.personalVisas {
            try (record.attachments ?? []).forEach { try $0.validateIntegrity() }
        }
        try backup.profile?.photo?.validateIntegrity()
        return backup
    }

    static func requireCountryCode(_ code: String) throws {
        guard code.count == 3, code.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) }) else {
            throw UserDataBackupError.invalidCountryCode(code)
        }
    }

    static func requireUnique<T: Hashable & CustomStringConvertible>(_ values: [T]) throws {
        var seen = Set<T>()
        for value in values where !seen.insert(value).inserted {
            throw UserDataBackupError.duplicateRecord(value.description)
        }
    }
}

// MARK: - Validation (main actor: maps records to app models)

@MainActor extension UserDataBackup {
    /// Convenience for main-actor callers (e.g. tests): full decode + structural validation.
    /// For large files, prefer `decodeVerifyingMedia(from:)` in a background task,
    /// then `validate(checkMediaChecksums: false)` here.
    static func decode(from data: Data) throws -> UserDataBackup {
        let backup = try decodeVerifyingMedia(from: data)
        try backup.validate(checkMediaChecksums: false)
        return backup
    }

    /// Structural checks; checksums are optional because hashing large media is expensive.
    /// Intact media with an unsupported type or size passes here; the import plan skips it.
    func validate(checkMediaChecksums: Bool = true) throws {
        if let code = passport?.code { try Self.requireCountryCode(code) }
        if let entryPolicies {
            let overrideCodes = entryPolicies.overrides.map(\.countryCode)
            try (overrideCodes + entryPolicies.removedCountryCodes).forEach { try Self.requireCountryCode($0) }
            try Self.requireUnique(overrideCodes)
        }

        try Self.requireUnique(personalVisas.map(\.id))
        try Self.requireUnique(visits.map(\.id))
        try Self.requireUnique(wishlist.map(\.id))

        func check(_ media: BackupMedia) throws {
            if checkMediaChecksums { try media.validateIntegrity() } else { try media.validateStructure() }
        }

        for record in personalVisas {
            _ = try record.toModel(attachmentFileNames: [])
            let media = record.attachments ?? []
            try Self.requireUnique(media.map { $0.fileName.lowercased() })
            try media.forEach(check)
        }
        try visits.forEach { _ = try $0.toModel() }
        try wishlist.forEach { _ = try $0.toModel() }
        if let photo = profile?.photo { try check(photo) }
    }
}

// MARK: - Export

struct UserDataExportResult {
    var backup: UserDataBackup
    /// Files left out because this app version can't include them (unsupported type / too large).
    var skippedFileNames: [String]
}

@MainActor extension UserDataBackup {
    /// - Parameters:
    ///   - profilePhoto: nil = do not include the profile photo.
    ///   - attachmentLoader: nil = records only (no visa attachments).
    ///   - bundledDefaults: bundled entry policies for `data.passportCode`.
    static func make(from data: AppData,
                     displayName: String?,
                     profilePhoto: BackupFile?,
                     attachmentLoader: ((PersonalVisa) throws -> [BackupFile])?,
                     bundledDefaults: [DefaultVisaEntry],
                     exportedAt: Date = Date()) throws -> UserDataExportResult {
        var skipped: [String] = []

        func pack(_ files: [BackupFile], purpose: BackupMedia.Purpose) -> [BackupMedia] {
            var names = Set<String>()
            var packed: [BackupMedia] = []
            for file in files {
                if names.insert(file.fileName.lowercased()).inserted,
                   let media = BackupMedia.forExport(file, purpose: purpose) {
                    packed.append(media)
                } else {
                    skipped.append(file.fileName)
                }
            }
            return packed
        }

        var visaRecords: [PersonalVisaRecord] = []
        for visa in data.personalVisas {
            var media: [BackupMedia]? = nil
            if let attachmentLoader { media = pack(try attachmentLoader(visa), purpose: .attachment) }
            visaRecords.append(PersonalVisaRecord(visa, attachments: media))
        }

        var photo: BackupMedia? = nil
        if let profilePhoto { photo = pack([profilePhoto], purpose: .profilePhoto).first }

        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let backup = UserDataBackup(
            kind: .fullBackup,
            exportedAt: exportedAt,
            app: .current,
            profile: Profile(displayName: name?.isEmpty == false ? name : nil, photo: photo),
            passport: Passport(code: data.passportCode),
            entryPolicies: EntryPolicies.diff(current: data.defaultVisas, bundled: bundledDefaults),
            personalVisas: visaRecords,
            visits: data.visits.map { VisitRecord($0) },
            wishlist: data.plannedTrips.map { WishlistRecord($0) }
        )
        try backup.validate(checkMediaChecksums: false)   // exports pass the same checks as imports
        return UserDataExportResult(backup: backup, skippedFileNames: skipped)
    }
}

// MARK: - Import planning (pure, no side effects)

struct UserDataImportPlan {
    let mode: UserDataImportMode
    /// Pass to AppState.commitRestoredData(_:).
    var data: AppData
    var summary: UserDataRestoreSummary
    /// Visa ID → the full new set of files for that visa (may be empty = clear the folder).
    /// Visas not listed here keep their existing folder untouched.
    var attachmentsToStage: [UUID: [BackupMedia]]
    /// Pass to UserProfileStore.restore(_:mode:). Unsupported photos are already removed.
    var profile: UserDataBackup.Profile?
}

@MainActor extension UserDataBackup {
    /// Replace: the file wins (passport, entry policies, all records). Visas whose attachments are
    ///          not included in the file keep this device's files.
    /// Merge:   local wins. Passport and entry policies are kept; only new IDs are added.
    ///          Importing the same file twice adds nothing the second time.
    /// Both:    a wishlist item whose ID exists as a Visit is treated as completed and removed
    ///          (PlannedTrip.visitDraft reuses the trip ID).
    ///
    /// Expects a backup whose checksums were already verified (`decodeVerifyingMedia`);
    /// only cheap structural checks are repeated here, so it is safe to call for live previews.
    func makeImportPlan(mode: UserDataImportMode,
                        local: AppData,
                        bundledDefaults: (String) -> [DefaultVisaEntry]) throws -> UserDataImportPlan {
        guard kind == .fullBackup else { throw UserDataBackupError.unsupportedKind(kind.rawValue) }
        try validate(checkMediaChecksums: false)

        var result = local
        var summary = UserDataRestoreSummary(mode: mode)
        var staged: [UUID: [BackupMedia]] = [:]

        func usable(_ media: [BackupMedia]) -> [BackupMedia] {
            let supported = media.filter { $0.isSupported(for: .attachment) }
            summary.mediaSkipped += media.count - supported.count
            return supported
        }

        switch mode {
        case .replace:
            let passportCode = passport?.code ?? local.passportCode
            result.passportCode = passportCode
            summary.passportChanged = passportCode != local.passportCode

            if let entryPolicies {
                let applied = entryPolicies.applied(to: bundledDefaults(passportCode))
                result.defaultVisas = applied.entries
                summary.entryPoliciesSkipped = applied.skipped
                summary.entryPolicyEdits = entryPolicies.overrides.count - applied.skipped
                    + entryPolicies.removedCountryCodes.count
            } else if summary.passportChanged {
                result.defaultVisas = bundledDefaults(passportCode)
            } // else: not included in file and same passport → keep local edits

            let localVisas = Dictionary(local.personalVisas.map { ($0.id, $0) },
                                        uniquingKeysWith: { first, _ in first })
            var visas: [PersonalVisa] = []
            for record in personalVisas {
                if let media = record.attachments {
                    let files = usable(media)
                    staged[record.id] = files   // may be empty → folder cleared
                    visas.append(try record.toModel(attachmentFileNames: files.map(\.fileName)))
                } else {
                    visas.append(try record.toModel(
                        attachmentFileNames: localVisas[record.id]?.attachmentFileNames ?? []))
                }
            }
            result.personalVisas = visas
            result.visits = try visits.map { try $0.toModel() }
            result.plannedTrips = try wishlist.map { try $0.toModel() }

        case .merge:
            var visaIDs = Set(local.personalVisas.map(\.id))
            for record in personalVisas {
                guard visaIDs.insert(record.id).inserted else { summary.personalVisasSkipped += 1; continue }
                let files = usable(record.attachments ?? [])
                if record.attachments != nil { staged[record.id] = files }
                result.personalVisas.append(try record.toModel(attachmentFileNames: files.map(\.fileName)))
                summary.personalVisasAdded += 1
            }

            var visitIDs = Set(local.visits.map(\.id))
            for record in visits {
                guard visitIDs.insert(record.id).inserted else { summary.visitsSkipped += 1; continue }
                result.visits.append(try record.toModel())
                summary.visitsAdded += 1
            }

            var tripIDs = Set(local.plannedTrips.map(\.id))
            for record in wishlist {
                guard !visitIDs.contains(record.id), tripIDs.insert(record.id).inserted else {
                    summary.wishlistSkipped += 1; continue
                }
                result.plannedTrips.append(try record.toModel())
                summary.wishlistAdded += 1
            }
        }

        // A planned trip completed on either device now exists as a Visit with the same ID.
        let allVisitIDs = Set(result.visits.map(\.id))
        let tripCountBefore = result.plannedTrips.count
        result.plannedTrips.removeAll { allVisitIDs.contains($0.id) }
        summary.wishlistResolvedAsVisited = tripCountBefore - result.plannedTrips.count

        if mode == .replace {
            summary.personalVisasAdded = result.personalVisas.count
            summary.visitsAdded = result.visits.count
            summary.wishlistAdded = result.plannedTrips.count
        }
        summary.attachmentsRestored = staged.values.reduce(0) { $0 + $1.count }

        var importedProfile = profile
        if let photo = importedProfile?.photo, !photo.isSupported(for: .profilePhoto) {
            importedProfile?.photo = nil      // nil = "not included" → local photo kept
            summary.mediaSkipped += 1
        }

        return UserDataImportPlan(mode: mode, data: result, summary: summary,
                                  attachmentsToStage: staged, profile: importedProfile)
    }
}

// MARK: - Private helpers

/// Minimal header used to reject non-backup / newer files before the full decode.
nonisolated private struct BackupHeader: Decodable {
    var format: String?
    var schemaVersion: Int?
}
