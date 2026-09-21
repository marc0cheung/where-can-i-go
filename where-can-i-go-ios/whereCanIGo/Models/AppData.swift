import Foundation

struct AppData: Codable {
    var passportCode: String           // ISO3, defaults to "HKG"
    var defaultVisas: [DefaultVisaEntry]
    var personalVisas: [PersonalVisa]
    var visits: [Visit]

    init(passportCode: String,
         defaultVisas: [DefaultVisaEntry],
         personalVisas: [PersonalVisa],
         visits: [Visit] = []) {
        self.passportCode = passportCode
        self.defaultVisas = defaultVisas
        self.personalVisas = personalVisas
        self.visits = visits
    }

    // Custom decoding so app_data.json saved before `visits` existed still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        passportCode = try c.decode(String.self, forKey: .passportCode)
        defaultVisas = try c.decode([DefaultVisaEntry].self, forKey: .defaultVisas)
        personalVisas = try c.decode([PersonalVisa].self, forKey: .personalVisas)
        visits = try c.decodeIfPresent([Visit].self, forKey: .visits) ?? []
    }
}
