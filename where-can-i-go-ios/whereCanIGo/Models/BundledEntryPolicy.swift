import Foundation

struct BundledEntryPolicy: Decodable {
    let updatedAt: Date
    let entries: [DefaultVisaEntry]

    private enum CodingKeys: String, CodingKey {
        case updatedAt, entries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawUpdatedAt = try container.decode(String.self, forKey: .updatedAt)
        do {
            updatedAt = try Date(rawUpdatedAt, strategy: .iso8601.year().month().day())
        } catch {
            throw DecodingError.dataCorruptedError(
                forKey: .updatedAt,
                in: container,
                debugDescription: "Expected updatedAt in yyyy-MM-dd format."
            )
        }
        entries = try container.decode([DefaultVisaEntry].self, forKey: .entries)
    }
}
