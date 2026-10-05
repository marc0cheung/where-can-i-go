import Foundation

enum VisaCoverage: String, Codable, Hashable {
    case issuingCountry = "issuing_country"
    case schengenArea = "schengen_area"

    static let schengenCountryCodes: Set<String> = [
        "AUT", "BEL", "BGR", "HRV", "CZE", "DNK", "EST", "FIN", "FRA", "DEU",
        "GRC", "HUN", "ISL", "ITA", "LVA", "LIE", "LTU", "LUX", "MLT", "NLD",
        "NOR", "POL", "PRT", "ROU", "SVK", "SVN", "ESP", "SWE", "CHE"
    ]
}

struct PersonalVisa: Codable, Identifiable, Hashable {
    let id: UUID
    let countryCode: String   // ISO3
    let visaType: String
    let duration: String
    let expiryDate: Date
    let notes: String?
    let attachmentFileNames: [String]
    let coverage: VisaCoverage

    init(id: UUID = UUID(),
         countryCode: String,
         visaType: String,
         duration: String,
         expiryDate: Date,
         notes: String? = nil,
         attachmentFileNames: [String] = [],
         coverage: VisaCoverage = .issuingCountry) {
        self.id = id
        self.countryCode = countryCode
        self.visaType = visaType
        self.duration = duration
        self.expiryDate = expiryDate
        self.notes = notes
        self.attachmentFileNames = attachmentFileNames
        self.coverage = VisaCoverage.schengenCountryCodes.contains(countryCode) ? coverage : .issuingCountry
    }

    private enum CodingKeys: String, CodingKey {
        case id, countryCode, visaType, duration, expiryDate, notes, attachmentFileNames, coverage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            countryCode: try container.decode(String.self, forKey: .countryCode),
            visaType: try container.decode(String.self, forKey: .visaType),
            duration: try container.decode(String.self, forKey: .duration),
            expiryDate: try container.decode(Date.self, forKey: .expiryDate),
            notes: try container.decodeIfPresent(String.self, forKey: .notes),
            attachmentFileNames: try container.decodeIfPresent([String].self, forKey: .attachmentFileNames) ?? [],
            coverage: try container.decodeIfPresent(VisaCoverage.self, forKey: .coverage) ?? .issuingCountry
        )
    }

    func covers(_ code: String) -> Bool {
        countryCode == code || (coverage == .schengenArea && VisaCoverage.schengenCountryCodes.contains(code))
    }
}
