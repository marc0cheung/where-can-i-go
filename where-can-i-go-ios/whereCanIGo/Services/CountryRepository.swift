import Foundation
import OSLog

enum CountryRepository {
    private static let logger = Logger(subsystem: "com.marcocheung.whereCanIGo", category: "CountryRepository")

    static func loadAllCountries() throws -> [Country] {
        guard let url = Bundle.main.url(forResource: "countries", withExtension: "json") else {
            logger.error("countries.json not found in main bundle.")
            return []
        }
        let data = try Data(contentsOf: url)
        let list = try JSONDecoder().decode([Country].self, from: data)
        return list.sorted {
            $0.localizedName().localizedCaseInsensitiveCompare($1.localizedName()) == .orderedAscending
        }
    }

    /// Loads the bundled policy named `default_visas_<ISO3>.json`.
    /// Returns nil when the file is missing.
    static func loadBundledEntryPolicy(passport code: String) throws -> BundledEntryPolicy? {
        let resource = "default_visas_\(code.uppercased())"
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json") else {
            logger.error("Bundled entry-policy data not found: \(resource, privacy: .public).json")
            return nil
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(BundledEntryPolicy.self, from: data)
    }

    static func loadDefaultVisas(passport code: String) throws -> [DefaultVisaEntry] {
        try loadBundledEntryPolicy(passport: code)?.entries ?? []
    }
}
