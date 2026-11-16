import Foundation
import OSLog

struct AirportInfo: Hashable {
    let iata: String
    let countryCode: String   // ISO3
    let city: String
    let latitude: Double
    let longitude: Double
}

enum AirportRepository {
    private static let logger = Logger(subsystem: "com.marcocheung.whereCanIGo", category: "AirportRepository")

    private struct CompactRecord: Decodable {
        let countryCode: String
        let city: String
        let latitude: Double
        let longitude: Double

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            countryCode = try container.decode(String.self)
            city = try container.decode(String.self)
            latitude = try container.decode(Double.self)
            longitude = try container.decode(Double.self)
        }
    }

    static let catalog: Result<[String: AirportInfo], Error> = Result {
        do {
            guard let url = Bundle.main.url(forResource: "airports_iata", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try decode(Data(contentsOf: url))
        } catch {
            logger.error("Unable to load airports_iata.json: \(error.localizedDescription)")
            throw error
        }
    }

    static func decode(_ data: Data) throws -> [String: AirportInfo] {
        let raw = try JSONDecoder().decode([String: CompactRecord].self, from: data)
        var map: [String: AirportInfo] = [:]
        map.reserveCapacity(raw.count)
        for (iata, record) in raw {
            let code = iata.uppercased()
            guard code.utf8.count == 3,
                  code.utf8.allSatisfy({ (65...90).contains($0) }),
                  record.countryCode.utf8.count == 3,
                  record.countryCode.utf8.allSatisfy({ (65...90).contains($0) }) else {
                continue
            }
            map[code] = AirportInfo(
                iata: code,
                countryCode: record.countryCode,
                city: record.city,
                latitude: record.latitude,
                longitude: record.longitude
            )
        }
        return map
    }

    static func lookup(_ iata: String) -> AirportInfo? {
        guard case .success(let map) = catalog else { return nil }
        return map[iata.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()]
    }
}
