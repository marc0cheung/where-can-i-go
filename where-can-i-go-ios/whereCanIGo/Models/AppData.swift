import Foundation

struct AppData: Codable {
    var passportCode: String           // ISO3, defaults to "HKG"
    var defaultVisas: [DefaultVisaEntry]
    var personalVisas: [PersonalVisa]
}
