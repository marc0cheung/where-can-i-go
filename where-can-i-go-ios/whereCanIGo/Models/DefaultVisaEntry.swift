import Foundation

struct DefaultVisaEntry: Codable, Identifiable, Hashable {
    let countryCode: String   // ISO3
    let category: VisaCategory
    let duration: String?

    var id: String { countryCode }
}
