import Foundation

struct AppData: Codable {
    var passportCode: String           // ISO3, defaults to "HKG"
    var defaultVisas: [DefaultVisaEntry]
    var personalVisas: [PersonalVisa]
    var visits: [Visit]
    var plannedTrips: [PlannedTrip]

    init(passportCode: String,
         defaultVisas: [DefaultVisaEntry],
         personalVisas: [PersonalVisa],
         visits: [Visit] = [],
         plannedTrips: [PlannedTrip] = []) {
        self.passportCode = passportCode
        self.defaultVisas = defaultVisas
        self.personalVisas = personalVisas
        self.visits = visits
        self.plannedTrips = plannedTrips
    }

    // Custom decoding so app_data.json saved before `visits` existed still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        passportCode = try c.decode(String.self, forKey: .passportCode)
        defaultVisas = try c.decode([DefaultVisaEntry].self, forKey: .defaultVisas)
        personalVisas = try c.decode([PersonalVisa].self, forKey: .personalVisas)
        visits = try c.decodeIfPresent([Visit].self, forKey: .visits) ?? []
        plannedTrips = try c.decodeIfPresent([PlannedTrip].self, forKey: .plannedTrips) ?? []
    }

    mutating func completePlannedTrip(_ id: UUID, with visit: Visit) throws {
        guard plannedTrips.contains(where: { $0.id == id }) else { throw PlannedTripError.notFound }
        guard !visits.contains(where: { $0.id == id }) else { throw PlannedTripError.alreadyCompleted }
        visits.append(Visit(id: id, countryCode: visit.countryCode,
                            startDate: visit.startDate, endDate: visit.endDate,
                            purpose: visit.purpose, location: visit.location, notes: visit.notes))
        plannedTrips.removeAll { $0.id == id }
    }
}
