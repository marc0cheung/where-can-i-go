import Foundation

struct Country: Codable, Identifiable, Hashable {
    /// ISO 3166-1 alpha-3
    let code: String
    /// ISO 3166-1 alpha-2 (used to compute the flag emoji at runtime if needed)
    let iso2: String
    let name: String
    let flag: String

    var id: String { code }
}
