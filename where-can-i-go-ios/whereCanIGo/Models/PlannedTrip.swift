import Foundation

enum PlannedTripError: Error {
    case notFound
    case alreadyCompleted
}

enum PlannedDurationMode: String, Codable, CaseIterable, Identifiable {
    case notSet
    case estimatedDays
    case dates

    var id: String { rawValue }
}

struct PlannedTrip: Codable, Identifiable, Hashable {
    let id: UUID
    let countryCode: String
    let createdAt: Date
    var location: String?
    var purpose: VisitPurpose
    var notes: String?
    var durationMode: PlannedDurationMode
    var estimatedDays: Int?
    var startDate: Date?
    var endDate: Date?

    init(id: UUID = UUID(), countryCode: String, createdAt: Date = Date(),
         location: String? = nil, purpose: VisitPurpose = .leisure, notes: String? = nil,
         durationMode: PlannedDurationMode = .notSet, estimatedDays: Int? = nil,
         startDate: Date? = nil, endDate: Date? = nil) {
        self.id = id
        self.countryCode = countryCode
        self.createdAt = createdAt
        let trimmedLocation = location?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.location = trimmedLocation?.isEmpty == false ? trimmedLocation : nil
        self.purpose = purpose
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.notes = trimmedNotes?.isEmpty == false ? trimmedNotes : nil
        self.durationMode = durationMode
        self.estimatedDays = durationMode == .estimatedDays ? estimatedDays : nil
        self.startDate = durationMode == .dates ? startDate.map { Calendar.current.startOfDay(for: $0) } : nil
        self.endDate = durationMode == .dates ? endDate.map { Calendar.current.startOfDay(for: $0) } : nil
    }

    var plannedDayCount: Int? {
        switch durationMode {
        case .notSet:
            return nil
        case .estimatedDays:
            guard let estimatedDays, estimatedDays > 0 else { return nil }
            return estimatedDays
        case .dates:
            guard let startDate, let endDate else { return nil }
            let calendar = Calendar.current
            let days = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: startDate),
                to: calendar.startOfDay(for: endDate)
            ).day ?? 0
            return days >= 0 ? days + 1 : nil
        }
    }

    var visitDraft: Visit {
        Visit(id: id, countryCode: countryCode,
              startDate: durationMode == .dates ? startDate : nil,
              endDate: durationMode == .dates ? endDate : nil,
              purpose: purpose, location: location, notes: notes)
    }
}