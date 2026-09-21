import SwiftUI

/// Reason for visiting a country, logged per trip.
enum VisitPurpose: String, Codable, CaseIterable, Hashable, Identifiable {
    case leisure  = "leisure"
    case business = "business"
    case family   = "family"
    case study    = "study"
    case transit  = "transit"
    case other    = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .leisure:  return "Leisure"
        case .business: return "Business"
        case .family:   return "Family / Friends"
        case .study:    return "Study"
        case .transit:  return "Transit"
        case .other:    return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .leisure:  return "beach.umbrella.fill"
        case .business: return "briefcase.fill"
        case .family:   return "person.2.fill"
        case .study:    return "graduationcap.fill"
        case .transit:  return "airplane"
        case .other:    return "mappin.and.ellipse"
        }
    }

    var color: Color {
        switch self {
        case .leisure:  return Color(red: 0.90, green: 0.55, blue: 0.20)
        case .business: return Color(red: 0.30, green: 0.45, blue: 0.75)
        case .family:   return Color(red: 0.85, green: 0.35, blue: 0.45)
        case .study:    return Color(red: 0.45, green: 0.35, blue: 0.75)
        case .transit:  return Color(red: 0.35, green: 0.60, blue: 0.65)
        case .other:    return Color(white: 0.55)
        }
    }
}
