import Foundation
import SwiftUI
import Combine
import OSLog

@MainActor
final class AppState: ObservableObject {
    @Published var isLoading: Bool = true
    @Published var needsPassportSelection: Bool = false
    @Published var attachmentProtectionError: String?
    @Published var data: AppData = AppData(passportCode: "HKG", defaultVisas: [], personalVisas: [])
    @Published var countries: [Country] = []
    @Published var selectedCountryCode: String? = nil
    @Published var pendingAddVisaCountryCode: String? = nil
    @Published var pendingAddVisitCountryCode: String? = nil
    @Published var pendingAddWishlistCountryCode: String? = nil
    @Published var diceSpinTarget: String? = nil
    @Published private(set) var visaReferenceDate: Date = Date()

    // MARK: Backup & restore state
    /// True while an import is being applied; UI should disable import/export and edits.
    @Published private(set) var isRestoring: Bool = false
    /// Increments every time restored data is committed (including rollbacks).
    /// Views can use `.onChange(of: appState.dataRevision)` or `.id(appState.dataRevision)` to rebuild caches.
    @Published private(set) var dataRevision: Int = 0
    /// Result of the last fully successful restore, for a success banner/alert.
    @Published private(set) var lastRestoreSummary: UserDataRestoreSummary? = nil

    private let store: DataStore

    init(store: DataStore? = nil) {
        self.store = store ?? DataStore()
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        protectVisaAttachments()
        // 1. Load static country list
        self.countries = (try? CountryRepository.loadAllCountries()) ?? []

        // 2. Try to load persisted state
        if let saved = try? store.loadAppData() {
            self.data = saved
            self.needsPassportSelection = false
        } else {
            // First launch -> show passport picker, pre-load HKG defaults so map renders something behind it.
            self.data.passportCode = "HKG"
            self.data.defaultVisas = (try? CountryRepository.loadDefaultVisas(passport: "HKG")) ?? []
            self.needsPassportSelection = true
        }
        self.isLoading = false
    }

    func protectVisaAttachments() {
        do {
            try VisaAttachmentStore.protectExistingFiles()
            attachmentProtectionError = nil
        } catch {
            Logger(subsystem: "com.marcocheung.whereCanIGo", category: "AttachmentProtection")
                .error("Unable to protect existing visa attachments: \(error.localizedDescription)")
            attachmentProtectionError = error.localizedDescription
        }
    }

    func completePassportSelection(_ code: String) {
        data.passportCode = code
        data.defaultVisas = (try? CountryRepository.loadDefaultVisas(passport: code)) ?? []
        needsPassportSelection = false
        save()
    }

    // MARK: - Mutations

    func addPersonalVisa(_ visa: PersonalVisa) {
        data.personalVisas.append(visa); save()
    }

    func updatePersonalVisa(_ visa: PersonalVisa) {
        guard let index = data.personalVisas.firstIndex(where: { $0.id == visa.id }) else { return }
        data.personalVisas[index] = visa
        save()
    }

    func removePersonalVisa(_ id: UUID) {
        data.personalVisas.removeAll { $0.id == id }
        VisaAttachmentStore.deleteFolder(for: id)
        save()
    }

    func addDefaultVisa(_ entry: DefaultVisaEntry) {
        data.defaultVisas.removeAll { $0.countryCode == entry.countryCode }
        data.defaultVisas.append(entry); save()
    }

    func removeDefaultVisa(_ code: String) {
        data.defaultVisas.removeAll { $0.countryCode == code }; save()
    }

    func resetDefaultsToBundled() {
        data.defaultVisas = (try? CountryRepository.loadDefaultVisas(passport: data.passportCode)) ?? []
        save()
    }

    // MARK: - Visits

    func addVisit(_ visit: Visit) {
        data.visits.append(visit); save()
    }

    func updateVisit(_ visit: Visit) {
        guard let index = data.visits.firstIndex(where: { $0.id == visit.id }) else { return }
        data.visits[index] = visit
        save()
    }

    func removeVisit(_ id: UUID) {
        data.visits.removeAll { $0.id == id }; save()
    }

    /// All visits for a country, most recent first.
    func visits(for code: String) -> [Visit] {
        data.visits
            .filter { $0.countryCode == code }
            .sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }

    /// Set of ISO3 codes with at least one logged visit.
    var visitedCountryCodes: Set<String> {
        Set(data.visits.map { $0.countryCode })
    }

    func plannedTrips(for code: String) -> [PlannedTrip] {
        data.plannedTrips.filter { $0.countryCode == code }.sorted {
            if $0.createdAt == $1.createdAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.createdAt > $1.createdAt
        }
    }

    func addPlannedTrip(_ trip: PlannedTrip) throws {
        var updated = data
        updated.plannedTrips.append(trip)
        try store.saveAppData(updated)
        data = updated
    }

    func updatePlannedTrip(_ trip: PlannedTrip) throws {
        var updated = data
        guard let index = updated.plannedTrips.firstIndex(where: { $0.id == trip.id }) else {
            throw PlannedTripError.notFound
        }
        updated.plannedTrips[index] = trip
        try store.saveAppData(updated)
        data = updated
    }

    func removePlannedTrip(_ id: UUID) throws {
        var updated = data
        guard updated.plannedTrips.contains(where: { $0.id == id }) else { throw PlannedTripError.notFound }
        updated.plannedTrips.removeAll { $0.id == id }
        try store.saveAppData(updated)
        data = updated
    }

    func completePlannedTrip(_ id: UUID, with visit: Visit) throws {
        var updated = data
        try updated.completePlannedTrip(id, with: visit)
        try store.saveAppData(updated)
        data = updated
    }

    // MARK: - Backup & Restore

    /// Bundled entry policies for a passport (used by export diffing and import rebuilding).
    func bundledDefaultVisas(for passportCode: String) -> [DefaultVisaEntry] {
        (try? CountryRepository.loadDefaultVisas(passport: passportCode)) ?? []
    }

    /// Read-only snapshot of the current data, for export or for rollback.
    func exportSnapshot() -> AppData {
        data
    }

    /// Marks the start of an import. Throws if another restore is already running.
    func beginRestore() throws {
        guard !isRestoring else { throw UserDataRestoreError.restoreInProgress }
        isRestoring = true
    }

    /// Call when an import finishes, usually from `defer`.
    func endRestore() {
        isRestoring = false
    }

    /// Persists and publishes restored data. Also used for rollback: `try appState.commitRestoredData(oldData)`.
    ///
    /// - Saves to disk first. If saving fails, in-memory state stays as it was and an error is thrown.
    /// - `defaultVisas` is used as-is (the import plan already rebuilt it).
    /// - Returns personal visa IDs that existed before but are gone now. The caller deletes their
    ///   attachment folders only after the whole restore has succeeded.
    @discardableResult
    func commitRestoredData(_ restored: AppData) throws -> Set<UUID> {
        var candidate = restored

        let passport = candidate.passportCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard passport.count == 3, passport.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            throw UserDataRestoreError.invalidPassportCode(candidate.passportCode)
        }
        candidate.passportCode = passport

        // 1. Persist. Memory is updated only after a successful save.
        do {
            try store.saveAppData(candidate)
        } catch {
            throw UserDataRestoreError.persistenceFailed(underlying: error)
        }

        // 2. Visas removed by this commit (for attachment cleanup by the caller).
        let removedVisaIDs = Set(data.personalVisas.map(\.id))
            .subtracting(candidate.personalVisas.map(\.id))

        // 3. Clear transient UI state that may point to records that no longer exist.
        selectedCountryCode = nil
        pendingAddVisaCountryCode = nil
        pendingAddVisitCountryCode = nil
        pendingAddWishlistCountryCode = nil
        diceSpinTarget = nil

        // 4. Publish the new state.
        data = candidate
        needsPassportSelection = false
        visaReferenceDate = Date()
        dataRevision &+= 1

        return removedVisaIDs
    }

    /// Call once, only after data, attachments and profile have all been restored successfully.
    func publishRestoreSummary(_ summary: UserDataRestoreSummary) {
        lastRestoreSummary = summary
        NotificationCenter.default.post(
            name: .userDataDidRestore,
            object: self,
            userInfo: ["summary": summary]
        )
    }

    /// Call after the success banner/alert is dismissed.
    func clearLastRestoreSummary() {
        lastRestoreSummary = nil
    }

    // MARK: - Helpers

    func visaCategory(for code: String) -> VisaCategory {
        visaEligibility(for: code).category
    }

    func visaEligibility(for code: String, on date: Date? = nil) -> VisaEligibility {
        VisaEligibility(
            countryCode: code,
            defaultCategory: data.defaultVisas.first(where: { $0.countryCode == code })?.category ?? .visaRequired,
            personalVisas: data.personalVisas,
            date: date ?? visaReferenceDate
        )
    }

    func refreshVisaValidity() {
        visaReferenceDate = Date()
    }

    func country(for code: String) -> Country? {
        countries.first(where: { $0.code == code })
    }

    func save() {
        try? store.saveAppData(data)
    }

    // MARK: - Selection

    func selectCountry(code: String?) {
        withAnimation(.smooth(duration: 0.25)) {
            selectedCountryCode = code
        }
    }
}
