import Foundation

nonisolated enum FlightyImportError: LocalizedError, Equatable, Sendable {
    case fileTooLarge
    case invalidEncoding
    case notAFlightyCSV
    case noCompletedFlights
    case airportCatalogUnavailable

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            return String(localized: "flighty.error.fileTooLarge")
        case .invalidEncoding:
            return String(localized: "flighty.error.invalidEncoding")
        case .notAFlightyCSV:
            return String(localized: "flighty.error.notAFlightyCSV")
        case .noCompletedFlights:
            return String(localized: "flighty.error.noCompletedFlights")
        case .airportCatalogUnavailable:
            return String(localized: "flighty.error.airportCatalogUnavailable")
        }
    }
}

/// Calendar day independent of time zone, so airport-local dates stay exact on any device.
nonisolated struct FlightyDay: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    static func from(_ date: Date, calendar: Calendar = .current) -> Self {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return Self(year: comps.year ?? 1970, month: comps.month ?? 1, day: comps.day ?? 1)
    }

    func toDate(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
            .map { calendar.startOfDay(for: $0) } ?? Date.distantPast
    }

    func days(to other: Self) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let start = cal.date(from: DateComponents(year: year, month: month, day: day)),
              let end = cal.date(from: DateComponents(year: other.year, month: other.month, day: other.day)) else {
            return 0
        }
        return cal.dateComponents([.day], from: start, to: end).day ?? 0
    }
}

/// Airport-local wall-clock date and optional time of day.
nonisolated struct FlightyLocalTime: Hashable, Comparable, Sendable {
    let day: FlightyDay
    let hour: Int?
    let minute: Int?

    var hasClockTime: Bool { hour != nil && minute != nil }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.day != rhs.day { return lhs.day < rhs.day }
        return (lhs.hour ?? 0, lhs.minute ?? 0) < (rhs.hour ?? 0, rhs.minute ?? 0)
    }

    /// Elapsed minutes between two wall-clock timestamps in the same local time zone.
    func minutes(to other: Self) -> Int? {
        guard let h1 = hour, let m1 = minute, let h2 = other.hour, let m2 = other.minute else {
            return nil
        }
        return day.days(to: other.day) * 1_440 + (h2 * 60 + m2) - (h1 * 60 + m1)
    }
}

nonisolated struct FlightyFlight: Identifiable, Hashable, Sendable {
    let id: UUID
    let fromIATA: String
    let toIATA: String
    let airline: String?
    let flightNumber: String?
    let departure: FlightyLocalTime
    let arrival: FlightyLocalTime
    let purposeRawValue: String?

    var routeLabel: String { "\(fromIATA) → \(toIATA)" }
}

struct FlightyUnknownAirport: Identifiable, Hashable {
    var id: String { iata }
    let iata: String
    let flightCount: Int
    let sampleRoute: String
}

nonisolated struct FlightyParsedLog: Sendable {
    let flights: [FlightyFlight]
    let canceledSkipped: Int
    let futureSkipped: Int
    let duplicatesSkipped: Int
}

enum FlightyTransitPolicy: String, CaseIterable, Identifiable {
    case skip
    case includeAsTransit

    var id: String { rawValue }
}

enum FlightyImportGranularity: String, CaseIterable, Identifiable {
    case allTrips
    case newCountriesOnly

    var id: String { rawValue }
}

enum FlightySkipReason: Hashable {
    case transit(minutes: Int?)
    case alreadyLogged
    case alreadyVisitedCountry
}

struct FlightyStayItem: Identifiable, Hashable {
    let id: UUID
    var countryCode: String
    var startDay: FlightyDay
    var endDay: FlightyDay
    var cities: [String]
    var customLocation: String?
    var purpose: VisitPurpose
    var notes: String
    let flights: [FlightyFlight]
    let isShortTransit: Bool
    let transitMinutes: Int?
    let isOpenJaw: Bool

    var locationText: String {
        if let customLocation { return customLocation }
        return cities.joined(separator: ", ")
    }

    var dayCount: Int {
        max(0, startDay.days(to: endDay)) + 1
    }

    var canSplitFlights: Bool {
        flights.count > 1
    }

    func effectivePurpose(transitPolicy: FlightyTransitPolicy) -> VisitPurpose {
        if isShortTransit && transitPolicy == .includeAsTransit && purpose == .leisure {
            return .transit
        }
        return purpose
    }

    func toVisit(transitPolicy: FlightyTransitPolicy, calendar: Calendar = .current) -> Visit {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let loc = locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        return Visit(
            countryCode: countryCode,
            startDate: startDay.toDate(calendar: calendar),
            endDate: endDay.toDate(calendar: calendar),
            purpose: effectivePurpose(transitPolicy: transitPolicy),
            location: loc.isEmpty ? nil : loc,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes
        )
    }
}

// MARK: - CSV Parsing

nonisolated enum FlightyCSV {
    static let maxFileByteCount = 16 * 1024 * 1024

    static func readLog(from url: URL, referenceDate: Date = Date()) async throws -> FlightyParsedLog {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }
        try Task.checkCancellation()
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size >= 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard size <= maxFileByteCount else {
            throw FlightyImportError.fileTooLarge
        }
        let today = FlightyDay.from(referenceDate)
        let reader = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= maxFileByteCount else {
                throw FlightyImportError.fileTooLarge
            }
            guard let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .utf16) else {
                throw FlightyImportError.invalidEncoding
            }
            try Task.checkCancellation()
            return try parse(text, today: today)
        }
        return try await withTaskCancellationHandler {
            try await reader.value
        } onCancel: {
            reader.cancel()
        }
    }

    static func parse(_ csvText: String, today: FlightyDay) throws -> FlightyParsedLog {
        let rows = parseRFC4180(csvText)
        guard let headerRowIndex = rows.firstIndex(where: { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }) else {
            throw FlightyImportError.notAFlightyCSV
        }

        let headers = rows[headerRowIndex].enumerated().reduce(into: [String: Int]()) { dict, pair in
            let normalized = pair.element
                .replacingOccurrences(of: "\u{FEFF}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if !normalized.isEmpty, dict[normalized] == nil {
                dict[normalized] = pair.offset
            }
        }

        guard let fromCol = headers["from"],
              let toCol = headers["to"],
              headers["date"] != nil
                || headers["gate departure (scheduled)"] != nil
                || headers["gate departure (actual)"] != nil else {
            throw FlightyImportError.notAFlightyCSV
        }

        let dateCol = headers["date"]
        let airlineCol = headers["airline"]
        let flightCol = headers["flight"]
        let canceledCol = headers["canceled"] ?? headers["cancelled"]
        let reasonCol = headers["flight reason"] ?? headers["reason"]

        let depActualCols = [headers["gate departure (actual)"], headers["take off (actual)"]].compactMap { $0 }
        let depSchedCols = [headers["gate departure (scheduled)"], headers["take off (scheduled)"]].compactMap { $0 }
        let arrActualCols = [headers["gate arrival (actual)"], headers["landing (actual)"]].compactMap { $0 }
        let arrSchedCols = [headers["gate arrival (scheduled)"], headers["landing (scheduled)"]].compactMap { $0 }

        func field(_ row: [String], _ col: Int?) -> String {
            guard let col, col < row.count else { return "" }
            return row[col].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        struct IndexedCandidate {
            let rowOrder: Int
            let flight: FlightyFlight
            let completeness: Int
        }

        var rawCandidates: [IndexedCandidate] = []
        var canceledSkipped = 0
        var futureSkipped = 0

        for (offset, row) in rows.dropFirst(headerRowIndex + 1).enumerated() {
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                continue
            }

            let canceledText = field(row, canceledCol).lowercased()
            if canceledText == "true" || canceledText == "1" || canceledText == "yes" {
                canceledSkipped += 1
                continue
            }

            let fromIATA = field(row, fromCol).uppercased()
            let toIATA = field(row, toCol).uppercased()
            guard isValidIATA(fromIATA), isValidIATA(toIATA), fromIATA != toIATA else {
                continue
            }

            let depActual = depActualCols.lazy.compactMap { parseLocalTimestamp(field(row, $0)) }.first
            let depSched = depSchedCols.lazy.compactMap { parseLocalTimestamp(field(row, $0)) }.first
            let fallbackDay = dateCol.flatMap { parseDateOnly(field(row, $0)) }

            guard let departure = depActual ?? depSched ?? fallbackDay.map({ FlightyLocalTime(day: $0, hour: nil, minute: nil) }) else {
                continue
            }

            let arrActual = arrActualCols.lazy.compactMap { parseLocalTimestamp(field(row, $0)) }.first
            let arrSched = arrSchedCols.lazy.compactMap { parseLocalTimestamp(field(row, $0)) }.first
            let hasActualFlightTime = depActual != nil || arrActual != nil

            // Skip upcoming bookings while keeping same-day or time-zone-ahead flights that already have actual times.
            if !hasActualFlightTime && departure.day > today {
                futureSkipped += 1
                continue
            }

            var arrival = arrActual ?? arrSched ?? FlightyLocalTime(day: departure.day, hour: nil, minute: nil)
            if arrival.day < departure.day && arrival.day.days(to: departure.day) > 2 {
                arrival = FlightyLocalTime(day: departure.day, hour: arrival.hour, minute: arrival.minute)
            }

            let airline = nonEmpty(field(row, airlineCol))
            let flightNumber = nonEmpty(field(row, flightCol))
            let purposeRaw = parseReasonRawValue(field(row, reasonCol))
            let completeness = (depActual != nil ? 4 : 0)
                + (arrActual != nil ? 4 : 0)
                + (departure.hasClockTime ? 2 : 0)
                + (arrival.hasClockTime ? 2 : 0)
                + (purposeRaw != nil ? 1 : 0)

            rawCandidates.append(IndexedCandidate(
                rowOrder: offset,
                flight: FlightyFlight(
                    id: UUID(),
                    fromIATA: fromIATA,
                    toIATA: toIATA,
                    airline: airline,
                    flightNumber: flightNumber,
                    departure: departure,
                    arrival: arrival,
                    purposeRawValue: purposeRaw
                ),
                completeness: completeness
            ))
        }

        // Deduplicate codeshares or accidental double entries on the same date and route.
        let sorted = rawCandidates.sorted { lhs, rhs in
            if lhs.flight.departure != rhs.flight.departure {
                return lhs.flight.departure < rhs.flight.departure
            }
            if lhs.flight.arrival != rhs.flight.arrival {
                return lhs.flight.arrival < rhs.flight.arrival
            }
            return lhs.rowOrder < rhs.rowOrder
        }

        var deduped: [IndexedCandidate] = []
        var duplicatesSkipped = 0

        for candidate in sorted {
            if let matchIndex = deduped.lastIndex(where: { existing in
                existing.flight.departure.day == candidate.flight.departure.day
                    && existing.flight.fromIATA == candidate.flight.fromIATA
                    && existing.flight.toIATA == candidate.flight.toIATA
                    && areLikelySameDeparture(existing.flight.departure, candidate.flight.departure)
            }) {
                duplicatesSkipped += 1
                if candidate.completeness > deduped[matchIndex].completeness {
                    deduped[matchIndex] = candidate
                }
            } else {
                deduped.append(candidate)
            }
        }

        guard !deduped.isEmpty else {
            throw FlightyImportError.noCompletedFlights
        }

        return FlightyParsedLog(
            flights: deduped.map(\.flight),
            canceledSkipped: canceledSkipped,
            futureSkipped: futureSkipped,
            duplicatesSkipped: duplicatesSkipped
        )
    }

    private static func areLikelySameDeparture(_ a: FlightyLocalTime, _ b: FlightyLocalTime) -> Bool {
        guard let diff = a.minutes(to: b) else { return true }
        return abs(diff) <= 30
    }

    private static func isValidIATA(_ code: String) -> Bool {
        code.utf8.count == 3 && code.utf8.allSatisfy { (65...90).contains($0) }
    }

    private static func nonEmpty(_ text: String) -> String? {
        text.isEmpty ? nil : text
    }

    private static func parseReasonRawValue(_ text: String) -> String? {
        switch text.lowercased() {
        case "business", "work": return "business"
        case "leisure", "personal", "vacation", "holiday": return "leisure"
        case "family": return "family"
        case "study", "school", "education": return "study"
        case "transit", "connection": return "transit"
        case "": return nil
        default: return "other"
        }
    }

    /// Parses ISO-like airport-local timestamps such as `2024-01-12T04:34` or `2024-01-12T04:34:00+08:00`.
    static func parseLocalTimestamp(_ text: String) -> FlightyLocalTime? {
        guard text.utf8.count >= 10 else { return nil }
        let chars = Array(text.unicodeScalars)
        guard chars.count >= 10,
              chars[4] == "-" || chars[4] == "/",
              chars[7] == "-" || chars[7] == "/" else {
            return nil
        }
        guard let year = Int(String(String.UnicodeScalarView(chars[0..<4]))),
              let month = Int(String(String.UnicodeScalarView(chars[5..<7]))),
              let day = Int(String(String.UnicodeScalarView(chars[8..<10]))),
              isValidDay(year: year, month: month, day: day) else {
            return nil
        }
        let localDay = FlightyDay(year: year, month: month, day: day)
        guard chars.count >= 16,
              chars[10] == "T" || chars[10] == " " || chars[10] == "t",
              chars[13] == ":" else {
            return FlightyLocalTime(day: localDay, hour: nil, minute: nil)
        }
        guard let hour = Int(String(String.UnicodeScalarView(chars[11..<13]))),
              let minute = Int(String(String.UnicodeScalarView(chars[14..<16]))),
              (0...23).contains(hour), (0...59).contains(minute) else {
            return FlightyLocalTime(day: localDay, hour: nil, minute: nil)
        }
        return FlightyLocalTime(day: localDay, hour: hour, minute: minute)
    }

    /// Parses standalone date strings (`2024-04-05`, Excel `7/28/19`, `7/28/2019`, `2024/4/5`).
    static func parseDateOnly(_ text: String) -> FlightyDay? {
        if let ts = parseLocalTimestamp(text) {
            return ts.day
        }
        let separator: Character? = text.contains("/") ? "/" : (text.contains("-") ? "-" : (text.contains(".") ? "." : nil))
        guard let separator else { return nil }
        let parts = text.split(separator: separator).map { String($0).trimmingCharacters(in: .whitespaces) }
        guard parts.count == 3,
              let p0 = Int(parts[0]), let p1 = Int(parts[1]), let p2 = Int(parts[2]) else {
            return nil
        }
        let year: Int
        let month: Int
        let day: Int
        if parts[0].count == 4 {
            year = p0; month = p1; day = p2
        } else {
            year = p2 < 100 ? (p2 < 70 ? 2000 + p2 : 1900 + p2) : p2
            if separator == "." || p0 > 12 {
                day = p0; month = p1
            } else {
                month = p0; day = p1
            }
        }
        guard isValidDay(year: year, month: month, day: day) else { return nil }
        return FlightyDay(year: year, month: month, day: day)
    }

    private static func isValidDay(year: Int, month: Int, day: Int) -> Bool {
        guard (1900...2100).contains(year), (1...12).contains(month), (1...31).contains(day) else {
            return false
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let comps = DateComponents(year: year, month: month, day: day)
        guard let date = cal.date(from: comps) else { return false }
        return cal.component(.month, from: date) == month && cal.component(.day, from: date) == day
    }

    /// Minimal RFC 4180 parser supporting quoted fields, escaped quotes, and embedded line breaks.
    static func parseRFC4180(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = String()
        var inQuotes = false
        var iterator = text.unicodeScalars.makeIterator()
        var pendingScalar: UnicodeScalar?

        func nextScalar() -> UnicodeScalar? {
            if let s = pendingScalar {
                pendingScalar = nil
                return s
            }
            return iterator.next()
        }

        while let scalar = nextScalar() {
            if inQuotes {
                if scalar == "\"" {
                    if let peek = nextScalar() {
                        if peek == "\"" {
                            currentField.unicodeScalars.append("\"")
                        } else {
                            inQuotes = false
                            pendingScalar = peek
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    currentField.unicodeScalars.append(scalar)
                }
            } else {
                switch scalar {
                case "\"":
                    if currentField.isEmpty {
                        inQuotes = true
                    } else {
                        currentField.unicodeScalars.append(scalar)
                    }
                case ",":
                    currentRow.append(currentField)
                    currentField = ""
                case "\r":
                    if let peek = nextScalar(), peek != "\n" {
                        pendingScalar = peek
                    }
                    currentRow.append(currentField)
                    rows.append(currentRow)
                    currentRow = []
                    currentField = ""
                case "\n":
                    currentRow.append(currentField)
                    rows.append(currentRow)
                    currentRow = []
                    currentField = ""
                default:
                    currentField.unicodeScalars.append(scalar)
                }
            }
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }
        return rows
    }
}

// MARK: - Stay Reconstruction & Rules

enum FlightyImportEngine {
    static let domesticSplitGapDays = 14
    static let maxTransitMinutes = 24 * 60

    struct Analysis {
        let stays: [FlightyStayItem]
        let unknownAirports: [FlightyUnknownAirport]
        let detectedPrimaryBase: String?
        let frequentCountryCodes: [String]
    }

    private static func visitPurpose(for flight: FlightyFlight) -> VisitPurpose? {
        flight.purposeRawValue.flatMap(VisitPurpose.init(rawValue:))
    }

    static func analyze(
        flights: [FlightyFlight],
        airports: [String: AirportInfo],
        airportOverrides: [String: String] = [:]
    ) -> Analysis {
        func resolve(_ iata: String) -> (countryCode: String, city: String?)? {
            if let info = airports[iata] {
                return (info.countryCode, info.city.isEmpty ? nil : info.city)
            }
            if let countryCode = airportOverrides[iata] {
                return (countryCode, nil)
            }
            return nil
        }

        // 1. Track unknown IATA codes and country frequencies.
        var unknownCounts: [String: (count: Int, sample: String)] = [:]
        var countryTouches: [String: Int] = [:]

        for flight in flights {
            if let from = resolve(flight.fromIATA) {
                countryTouches[from.countryCode, default: 0] += 1
            } else {
                let old = unknownCounts[flight.fromIATA]
                unknownCounts[flight.fromIATA] = ((old?.count ?? 0) + 1, old?.sample ?? flight.routeLabel)
            }

            if let to = resolve(flight.toIATA) {
                countryTouches[to.countryCode, default: 0] += 1
            } else {
                let old = unknownCounts[flight.toIATA]
                unknownCounts[flight.toIATA] = ((old?.count ?? 0) + 1, old?.sample ?? flight.routeLabel)
            }
        }

        let unknownAirports = unknownCounts
            .map { FlightyUnknownAirport(iata: $0.key, flightCount: $0.value.count, sampleRoute: $0.value.sample) }
            .sorted { lhs, rhs in
                if lhs.flightCount != rhs.flightCount { return lhs.flightCount > rhs.flightCount }
                return lhs.iata < rhs.iata
            }

        let frequentCountries = countryTouches
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .map(\.key)

        // 2. Reconstruct chronological stays across countries.
        struct ActiveStay {
            var countryCode: String
            var startDay: FlightyDay
            var endDay: FlightyDay
            var cities: [String]
            var entryFromCountry: String?
            var entryTime: FlightyLocalTime?
            var domesticOriginIATA: String?
            var domesticLegCount: Int
            var flights: [FlightyFlight]
            var explicitPurposes: [VisitPurpose]
            var openJaw: Bool

            mutating func addCity(_ city: String?) {
                guard let city, !city.isEmpty, !cities.contains(city) else { return }
                cities.append(city)
            }

            mutating func addPurpose(_ purpose: VisitPurpose?) {
                if let purpose { explicitPurposes.append(purpose) }
            }
        }

        var completed: [FlightyStayItem] = []
        var active: ActiveStay?

        func finalizeActive(
            endDay: FlightyDay? = nil,
            exitToCountry: String? = nil,
            exitTime: FlightyLocalTime? = nil,
            markOpenJaw: Bool = false
        ) {
            guard var current = active else { return }
            active = nil
            if let endDay, endDay >= current.startDay {
                current.endDay = endDay
            }
            if markOpenJaw {
                current.openJaw = true
            }

            // A short layover (< 24h) is a transit only when continuing to a third country (A -> B -> C, A != C)
            // with no domestic legs in B. Same-day round-trips (A -> B -> A) remain real visits.
            var isTransit = false
            var layoverMinutes: Int?
            if let entryCountry = current.entryFromCountry,
               let exitCountry = exitToCountry,
               entryCountry != exitCountry,
               current.domesticLegCount == 0,
               let entryTime = current.entryTime,
               let exitTime {
                if let mins = entryTime.minutes(to: exitTime), mins >= 0, mins < maxTransitMinutes {
                    isTransit = true
                    layoverMinutes = mins
                }
            }

            let resolvedPurpose = current.explicitPurposes.first ?? .leisure
            completed.append(FlightyStayItem(
                id: UUID(),
                countryCode: current.countryCode,
                startDay: current.startDay,
                endDay: current.endDay,
                cities: current.cities,
                customLocation: nil,
                purpose: resolvedPurpose,
                notes: "",
                flights: current.flights,
                isShortTransit: isTransit,
                transitMinutes: layoverMinutes,
                isOpenJaw: current.openJaw
            ))
        }

        for flight in flights {
            let resolvedFrom = resolve(flight.fromIATA)
            let resolvedTo = resolve(flight.toIATA)

            switch (resolvedFrom, resolvedTo) {
            case let (from?, to?) where from.countryCode == to.countryCode:
                // Domestic flight inside a single country.
                if let existing = active, existing.countryCode == from.countryCode {
                    let gap = existing.endDay.days(to: flight.departure.day)
                    if existing.entryFromCountry != nil || gap <= domesticSplitGapDays {
                        active?.endDay = max(existing.endDay, flight.arrival.day)
                        active?.domesticLegCount += 1
                        active?.flights.append(flight)
                        active?.addCity(from.city)
                        active?.addCity(to.city)
                        active?.addPurpose(visitPurpose(for: flight))
                        // Pure overland/domestic trip settles once returning to its starting airport.
                        if existing.entryFromCountry == nil,
                           let origin = existing.domesticOriginIATA,
                           flight.toIATA == origin {
                            finalizeActive()
                        }
                        continue
                    } else {
                        finalizeActive()
                    }
                } else if let existing = active {
                    finalizeActive(markOpenJaw: existing.entryFromCountry != nil)
                }

                var fresh = ActiveStay(
                    countryCode: from.countryCode,
                    startDay: flight.departure.day,
                    endDay: max(flight.departure.day, flight.arrival.day),
                    cities: [],
                    entryFromCountry: nil,
                    entryTime: flight.departure,
                    domesticOriginIATA: flight.fromIATA,
                    domesticLegCount: 1,
                    flights: [flight],
                    explicitPurposes: [],
                    openJaw: false
                )
                fresh.addCity(from.city)
                fresh.addCity(to.city)
                fresh.addPurpose(visitPurpose(for: flight))
                active = fresh

            case let (from?, to?):
                // International flight from -> to.
                if let existing = active {
                    if existing.countryCode == from.countryCode {
                        active?.addCity(from.city)
                        active?.addPurpose(visitPurpose(for: flight))
                        active?.flights.append(flight)
                        finalizeActive(
                            endDay: flight.departure.day,
                            exitToCountry: to.countryCode,
                            exitTime: flight.departure
                        )
                    } else {
                        let hadForeignArrival = existing.entryFromCountry != nil
                        finalizeActive(markOpenJaw: hadForeignArrival)
                        completed.append(FlightyStayItem(
                            id: UUID(),
                            countryCode: from.countryCode,
                            startDay: flight.departure.day,
                            endDay: flight.departure.day,
                            cities: from.city.map { [$0] } ?? [],
                            customLocation: nil,
                            purpose: visitPurpose(for: flight) ?? .leisure,
                            notes: "",
                            flights: [flight],
                            isShortTransit: false,
                            transitMinutes: nil,
                            isOpenJaw: hadForeignArrival
                        ))
                    }
                } else {
                    completed.append(FlightyStayItem(
                        id: UUID(),
                        countryCode: from.countryCode,
                        startDay: flight.departure.day,
                        endDay: flight.departure.day,
                        cities: from.city.map { [$0] } ?? [],
                        customLocation: nil,
                        purpose: visitPurpose(for: flight) ?? .leisure,
                        notes: "",
                        flights: [flight],
                        isShortTransit: false,
                        transitMinutes: nil,
                        isOpenJaw: false
                    ))
                }

                var destinationStay = ActiveStay(
                    countryCode: to.countryCode,
                    startDay: flight.arrival.day,
                    endDay: flight.arrival.day,
                    cities: [],
                    entryFromCountry: from.countryCode,
                    entryTime: flight.arrival,
                    domesticOriginIATA: nil,
                    domesticLegCount: 0,
                    flights: [flight],
                    explicitPurposes: [],
                    openJaw: false
                )
                destinationStay.addCity(to.city)
                destinationStay.addPurpose(visitPurpose(for: flight))
                active = destinationStay

            case let (from?, nil):
                if let existing = active, existing.countryCode == from.countryCode {
                    active?.addCity(from.city)
                    active?.flights.append(flight)
                    finalizeActive(endDay: flight.departure.day, exitTime: flight.departure)
                } else {
                    finalizeActive(markOpenJaw: active?.entryFromCountry != nil)
                    completed.append(FlightyStayItem(
                        id: UUID(),
                        countryCode: from.countryCode,
                        startDay: flight.departure.day,
                        endDay: flight.departure.day,
                        cities: from.city.map { [$0] } ?? [],
                        customLocation: nil,
                        purpose: visitPurpose(for: flight) ?? .leisure,
                        notes: "",
                        flights: [flight],
                        isShortTransit: false,
                        transitMinutes: nil,
                        isOpenJaw: false
                    ))
                }

            case let (nil, to?):
                finalizeActive(markOpenJaw: active?.entryFromCountry != nil)
                var destinationStay = ActiveStay(
                    countryCode: to.countryCode,
                    startDay: flight.arrival.day,
                    endDay: flight.arrival.day,
                    cities: [],
                    entryFromCountry: nil,
                    entryTime: flight.arrival,
                    domesticOriginIATA: nil,
                    domesticLegCount: 0,
                    flights: [flight],
                    explicitPurposes: [],
                    openJaw: false
                )
                destinationStay.addCity(to.city)
                destinationStay.addPurpose(visitPurpose(for: flight))
                active = destinationStay

            case (nil, nil):
                break
            }
        }

        finalizeActive()

        return Analysis(
            stays: completed,
            unknownAirports: unknownAirports,
            detectedPrimaryBase: frequentCountries.first,
            frequentCountryCodes: Array(frequentCountries.prefix(5))
        )
    }

    /// Checks whether an imported stay overlaps an existing logged visit for the same country.
    static func matchesExistingVisit(
        _ stay: FlightyStayItem,
        existingVisits: [Visit],
        calendar: Calendar = .current
    ) -> Bool {
        existingVisits.contains { visit in
            guard visit.countryCode == stay.countryCode else { return false }
            guard let vStart = visit.startDate else { return false }
            let startDay = FlightyDay.from(vStart, calendar: calendar)
            let endDay = visit.endDate.map { FlightyDay.from($0, calendar: calendar) } ?? startDay
            return stay.startDay <= endDay && startDay <= stay.endDay
        }
    }

    /// Splits a multi-flight stay into one stay per flight relevant to that country.
    static func split(_ stay: FlightyStayItem, airports: [String: AirportInfo], overrides: [String: String]) -> [FlightyStayItem] {
        func city(for iata: String, matching country: String) -> String? {
            if let info = airports[iata], info.countryCode == country, !info.city.isEmpty {
                return info.city
            }
            return nil
        }

        let parts = stay.flights.map { flight -> FlightyStayItem in
            let fromCountry = airports[flight.fromIATA]?.countryCode ?? overrides[flight.fromIATA]
            let toCountry = airports[flight.toIATA]?.countryCode ?? overrides[flight.toIATA]
            let dayStart = toCountry == stay.countryCode && fromCountry != stay.countryCode
                ? flight.arrival.day
                : flight.departure.day
            let dayEnd = fromCountry == stay.countryCode && toCountry != stay.countryCode
                ? flight.departure.day
                : max(dayStart, flight.arrival.day)
            var cities: [String] = []
            if let c1 = city(for: flight.fromIATA, matching: stay.countryCode) { cities.append(c1) }
            if let c2 = city(for: flight.toIATA, matching: stay.countryCode), !cities.contains(c2) { cities.append(c2) }

            return FlightyStayItem(
                id: UUID(),
                countryCode: stay.countryCode,
                startDay: dayStart,
                endDay: dayEnd,
                cities: cities,
                customLocation: nil,
                purpose: visitPurpose(for: flight) ?? stay.purpose,
                notes: stay.notes,
                flights: [flight],
                isShortTransit: false,
                transitMinutes: nil,
                isOpenJaw: false
            )
        }
        return parts.isEmpty ? [stay] : parts
    }

    /// Merges two stays of the same country into one continuous stay.
    static func merge(_ first: FlightyStayItem, _ second: FlightyStayItem) -> FlightyStayItem {
        let ordered = first.startDay <= second.startDay ? (first, second) : (second, first)
        var combinedCities = ordered.0.cities
        for city in ordered.1.cities where !combinedCities.contains(city) {
            combinedCities.append(city)
        }
        var combinedFlights = ordered.0.flights
        for flight in ordered.1.flights where !combinedFlights.contains(flight) {
            combinedFlights.append(flight)
        }
        let customLoc: String?
        if ordered.0.customLocation != nil || ordered.1.customLocation != nil {
            let parts = [ordered.0.locationText, ordered.1.locationText]
                .flatMap { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                .filter { !$0.isEmpty }
            var unique: [String] = []
            for p in parts where !unique.contains(p) { unique.append(p) }
            customLoc = unique.joined(separator: ", ")
        } else {
            customLoc = nil
        }
        let mergedNotes = [ordered.0.notes, ordered.1.notes]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return FlightyStayItem(
            id: UUID(),
            countryCode: ordered.0.countryCode,
            startDay: min(ordered.0.startDay, ordered.1.startDay),
            endDay: max(ordered.0.endDay, ordered.1.endDay),
            cities: combinedCities,
            customLocation: customLoc,
            purpose: ordered.0.purpose,
            notes: mergedNotes,
            flights: combinedFlights,
            isShortTransit: false,
            transitMinutes: nil,
            isOpenJaw: false
        )
    }
}
