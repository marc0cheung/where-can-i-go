import Foundation

/// A single trip to a country. Multiple visits can share the same countryCode.
struct Visit: Codable, Identifiable, Hashable {
    let id: UUID
    let countryCode: String   // ISO3
    var startDate: Date?
    var endDate: Date?
    var purpose: VisitPurpose
    var notes: String?

    init(id: UUID = UUID(),
         countryCode: String,
         startDate: Date? = nil,
         endDate: Date? = nil,
         purpose: VisitPurpose = .leisure,
         notes: String? = nil) {
        self.id = id
        self.countryCode = countryCode
        self.startDate = startDate
        self.endDate = endDate
        self.purpose = purpose
        self.notes = notes
    }

    /// Whole days spent, inclusive of both endpoints, when both dates are set.
    var dayCount: Int? {
        guard let startDate, let endDate else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: startDate),
                                      to: cal.startOfDay(for: endDate)).day ?? 0
        return max(0, days) + 1
    }
}
