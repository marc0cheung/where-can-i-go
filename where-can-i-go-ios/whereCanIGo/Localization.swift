import Foundation

extension Country {
    func localizedName(locale: Locale = .autoupdatingCurrent) -> String {
        if iso2.uppercased() == "CN", let override = Self.chinaName(for: locale) {
            return override
        }
        return locale.localizedString(forRegionCode: iso2) ?? name
    }

    private static func chinaName(for locale: Locale) -> String? {
        let language = locale.language
        switch language.languageCode?.identifier {
        case "zh":
            if let script = language.script?.identifier {
                return script == "Hant" ? "中國" : "中国"
            }
            switch language.region?.identifier {
            case "TW", "HK", "MO": return "中國"
            default: return "中国"
            }
        case "en":
            return "China"
        default:
            return nil
        }
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