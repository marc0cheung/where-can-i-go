import Foundation

struct Airline: Decodable, Identifiable {
    let id: String
    let name: String
    let logoAssetName: String
    let destinationCountryCodes: Set<String>

    var localizedName: String {
        String(localized: String.LocalizationValue(name))
    }
}

enum AirlineRepository {
    static let catalog: Result<[Airline], Error> = Result {
        do {
            guard let url = Bundle.main.url(forResource: "airline_destinations", withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try decode(Data(contentsOf: url))
        } catch {
            print("[WhereCanIGo] Unable to load airline_destinations.json: \(error)")
            throw error
        }
    }

    static func decode(_ data: Data) throws -> [Airline] {
        let airlines = try JSONDecoder().decode([Airline].self, from: data)
        guard !airlines.isEmpty,
              Set(airlines.map(\.id)).count == airlines.count,
              airlines.allSatisfy({ airline in
                  !airline.id.isEmpty && !airline.name.isEmpty && !airline.logoAssetName.isEmpty &&
                  !airline.destinationCountryCodes.isEmpty &&
                  airline.destinationCountryCodes.allSatisfy { code in
                      code.utf8.count == 3 && code.utf8.allSatisfy { (65...90).contains($0) }
                  }
              }) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "Airlines must have unique IDs, names, logo assets, and ISO3 destinations."
            ))
        }
        return airlines
    }

    static func destinationCodes(for selectedIDs: Set<String>, in airlines: [Airline]) -> Set<String> {
        airlines.filter { selectedIDs.contains($0.id) }
            .reduce(into: Set<String>()) { $0.formUnion($1.destinationCountryCodes) }
    }
}
