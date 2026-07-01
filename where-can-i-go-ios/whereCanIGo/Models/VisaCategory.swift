import SwiftUI

enum VisaCategory: String, Codable, CaseIterable, Hashable {
    case visaFree       = "visa_free"
    case visaOnArrival  = "visa_on_arrival"
    case eta            = "eta"
    case myVisa         = "my_visa"
    case visaRequired   = "visa_required"

    var displayName: String {
        switch self {
        case .visaFree:      return "Visa Free"
        case .visaOnArrival: return "Visa on Arrival"
        case .eta:           return "ETA"
        case .myVisa:        return "My Visa"
        case .visaRequired:  return "Visa Required"
        }
    }

    /// Palette matched to the web prototype.
    var color: Color {
        switch self {
        case .visaFree:      return Color(red: 0.16, green: 0.42, blue: 0.42)
        case .visaOnArrival: return Color(red: 0.28, green: 0.55, blue: 0.55)
        case .eta:           return Color(red: 0.38, green: 0.62, blue: 0.68)
        case .myVisa:        return Color(red: 0.55, green: 0.72, blue: 0.58)
        case .visaRequired:  return Color(white: 0.85)
        }
    }
}
