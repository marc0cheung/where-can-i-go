import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var isLoading: Bool = true
    @Published var needsPassportSelection: Bool = false
    @Published var data: AppData = AppData(passportCode: "HKG", defaultVisas: [], personalVisas: [])
    @Published var countries: [Country] = []
    @Published var selectedCountryCode: String? = nil
    @Published var pendingAddVisaCountryCode: String? = nil
    @Published var diceSpinTarget: String? = nil

    private let store = DataStore()

    // MARK: - Lifecycle

    func bootstrap() async {
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

    func removePersonalVisa(_ id: UUID) {
        data.personalVisas.removeAll { $0.id == id }; save()
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

    // MARK: - Helpers

    func visaCategory(for code: String) -> VisaCategory {
        if data.personalVisas.contains(where: { $0.countryCode == code }) { return .myVisa }
        if let entry = data.defaultVisas.first(where: { $0.countryCode == code }) { return entry.category }
        return .visaRequired
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
