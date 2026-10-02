import Foundation

struct DefaultVisaEntry: Codable, Identifiable, Hashable {
    let countryCode: String   // ISO3
    let category: VisaCategory
    let duration: String?
    var remark: String? = nil

    var id: String { countryCode }
}

extension DefaultVisaEntry {
    private enum CodingKeys: String, CodingKey {
        case countryCode, category, duration, remark
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        countryCode = try container.decode(String.self, forKey: .countryCode)
        category = try container.decode(VisaCategory.self, forKey: .category)
        let storedDuration = try container.decodeIfPresent(String.self, forKey: .duration)
        if container.contains(.remark) {
            duration = storedDuration
            remark = try container.decodeIfPresent(String.self, forKey: .remark)
        } else {
            let fields = Self.splitLegacyDuration(storedDuration)
            duration = fields.duration
            remark = fields.remark
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(countryCode, forKey: .countryCode)
        try container.encode(category, forKey: .category)
        try container.encode(duration, forKey: .duration)
        try container.encode(remark, forKey: .remark)
    }

    private static func splitLegacyDuration(_ value: String?) -> (duration: String?, remark: String?) {
        guard let value, !value.isEmpty else { return (value, nil) }

        switch value {
        case "Home Sweet Home":
            return (nil, value)
        case "2 weeks (single entry) or 1 month (multiple entry)":
            return ("2 weeks or 1 month", value)
        case "45 days under Guam-CNMI waiver with prior authorization and direct Taiwan flight; or 90 days with ESTA":
            return ("45 days or 90 days", value)
        case "Conditional visa-free: 30 days for tourist groups of 5+ with prepaid hotel and return tickets":
            return ("30 days", value)
        default:
            break
        }

        let pattern = #"(?i)^(?:(?:up to|maximum) )?\d+(?: to \d+)? (?:days?|weeks?|months?)(?: to \d+ (?:days?|weeks?|months?))?(?: within \d+ (?:days?|months?)| per (?:visit|calendar year))?(?![a-z])"#
        var durations: [String] = []
        var remarks: [String] = []
        let parts = value.components(separatedBy: ";")
        for part in parts {
            let text = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if text.lowercased() == "varies" || text.lowercased() == "stay varies" {
                durations.append("varies")
            } else if let range = text.range(of: pattern, options: .regularExpression) {
                durations.append(String(text[range]))
                let remainder = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !remainder.isEmpty { remarks.append(remainder) }
            } else {
                remarks.append(text)
            }
        }

        if durations.isEmpty, parts.count == 1,
           !value.localizedCaseInsensitiveContains("required") {
            return (value, nil)
        }
        return (
            durations.isEmpty ? nil : durations.joined(separator: "; "),
            remarks.isEmpty ? nil : remarks.joined(separator: "; ")
        )
    }
}
