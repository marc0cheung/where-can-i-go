import Foundation

enum CountryRepository {
    static func loadAllCountries() throws -> [Country] {
        guard let url = Bundle.main.url(forResource: "countries", withExtension: "json") else {
            print("[WhereCanIGo] countries.json not found in main bundle.")
            return []
        }
        let data = try Data(contentsOf: url)
        let list = try JSONDecoder().decode([Country].self, from: data)
        return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Loads bundled defaults named `default_visas_<ISO3>.json`.
    /// Returns an empty array if the file does not exist (no crash).
    static func loadDefaultVisas(passport code: String) throws -> [DefaultVisaEntry] {
        let resource = "default_visas_\(code.uppercased())"
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json") else {
            print("[WhereCanIGo] \(resource).json not bundled - returning empty default list.")
            return []
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([DefaultVisaEntry].self, from: data)
    }
}
