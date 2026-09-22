import Foundation

extension Country {
    func localizedName(locale: Locale = .autoupdatingCurrent) -> String {
        locale.localizedString(forRegionCode: iso2) ?? name
    }
}

extension VisaCategory {
    var localizedDisplayName: String {
        switch self {
        case .visaFree: String(localized: "Visa Free")
        case .visaOnArrival: String(localized: "Visa on Arrival")
        case .eta: String(localized: "ETA")
        case .myVisa: String(localized: "My Visa")
        case .visaRequired: String(localized: "Visa Required")
        }
    }
}

extension VisitPurpose {
    var localizedDisplayName: String {
        switch self {
        case .leisure: String(localized: "Leisure")
        case .business: String(localized: "Business")
        case .family: String(localized: "Family")
        case .study: String(localized: "Study")
        case .transit: String(localized: "Transit")
        case .other: String(localized: "Other")
        }
    }
}