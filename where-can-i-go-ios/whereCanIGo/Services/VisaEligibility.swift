import Foundation

struct VisaEligibility {
    let category: VisaCategory
    let sourceVisa: PersonalVisa?

    init(countryCode: String,
         defaultCategory: VisaCategory,
         personalVisas: [PersonalVisa],
         date: Date = Date(),
         calendar: Calendar = .current) {
        if defaultCategory == .visaFree {
            category = .visaFree
            sourceVisa = nil
            return
        }

        let today = calendar.startOfDay(for: date)
        sourceVisa = personalVisas
            .filter { $0.covers(countryCode) && calendar.startOfDay(for: $0.expiryDate) >= today }
            .sorted { first, second in
                let firstIsDirect = first.countryCode == countryCode
                let secondIsDirect = second.countryCode == countryCode
                if firstIsDirect != secondIsDirect { return firstIsDirect }
                if first.expiryDate != second.expiryDate { return first.expiryDate > second.expiryDate }
                return first.id.uuidString < second.id.uuidString
            }
            .first
        category = sourceVisa == nil ? defaultCategory : .myVisa
    }

    var isAccessible: Bool {
        category == .visaFree || category == .visaOnArrival || category == .myVisa
    }
}