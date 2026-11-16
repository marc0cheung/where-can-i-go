import SwiftUI

struct FlightyImportView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let parsedLog: FlightyParsedLog

    @State private var airports: [String: AirportInfo] = [:]
    @State private var airportOverrides: [String: String] = [:]
    @State private var stays: [FlightyStayItem] = []
    @State private var unknownAirports: [FlightyUnknownAirport] = []
    @State private var frequentCountryCodes: [String] = []
    @State private var excludedBaseCountries: Set<String> = []
    @State private var manualSelection: [UUID: Bool] = [:]

    @State private var transitPolicy: FlightyTransitPolicy = .skip
    @State private var granularity: FlightyImportGranularity = .allTrips
    @State private var groupingMode: GroupingMode = .byCountry
    @State private var showSkipped = false

    @State private var didInitialize = false
    @State private var showBaseCountryPicker = false
    @State private var pendingBaseCountry: Country?
    @State private var resolvingAirport: FlightyUnknownAirport?
    @State private var pendingAirportCountry: Country?
    @State private var editingStay: FlightyStayItem?

    @State private var isSaving = false
    @State private var errorMessage: String?

    private enum GroupingMode: String, CaseIterable, Identifiable {
        case byCountry
        case timeline
        var id: String { rawValue }
    }

    private struct CountryGroup: Identifiable {
        let countryCode: String
        let stays: [FlightyStayItem]
        var id: String { countryCode }

        var totalDays: Int {
            stays.reduce(0) { $0 + $1.dayCount }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                summarySection
                baseCountriesSection
                rulesSection
                if !unknownAirports.isEmpty {
                    unknownAirportsSection
                }
                tripsSection
                if !skippedEntries.isEmpty {
                    skippedSection
                }
            }
            .disabled(isSaving)
            .navigationTitle("flighty.title")
            .centeredNavigationTitle("flighty.title")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        commitImport()
                    } label: {
                        if selectedStays.isEmpty {
                            Text("flighty.import.action")
                        } else {
                            Text(String(
                                format: String(localized: "flighty.import.actionCount"),
                                locale: .current,
                                selectedStays.count
                            ))
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedStays.isEmpty || isSaving)
                }
            }
            .sheet(isPresented: $showBaseCountryPicker) {
                CountryPickerSheet(selected: $pendingBaseCountry)
            }
            .onChange(of: pendingBaseCountry) { _, picked in
                guard let picked else { return }
                withAnimation(.snappy) {
                    _ = excludedBaseCountries.insert(picked.code)
                }
                pendingBaseCountry = nil
            }
            .sheet(item: $resolvingAirport) { unknown in
                CountryPickerSheet(selected: Binding(
                    get: { pendingAirportCountry },
                    set: { picked in
                        pendingAirportCountry = nil
                        if let picked {
                            airportOverrides[unknown.iata] = picked.code
                            rebuildAnalysis(resetDefaults: false)
                        }
                    }
                ))
            }
            .sheet(item: $editingStay) { stay in
                FlightyStayEditorSheet(
                    stay: stay,
                    sameCountryPeers: nonBaseStays.filter { $0.countryCode == stay.countryCode && $0.id != stay.id },
                    onSave: { updated in
                        updateStay(updated)
                    },
                    onSplit: stay.canSplitFlights ? {
                        splitStay(stay)
                    } : nil,
                    onMerge: { other in
                        mergeStays(stay, other)
                    }
                )
            }
            .alert("import.error.title", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(verbatim: errorMessage ?? "")
            }
            .task {
                guard !didInitialize else { return }
                didInitialize = true
                initializePreview()
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section {
            HStack(spacing: 0) {
                statColumn(
                    value: parsedLog.flights.count.formatted(),
                    label: "flighty.summary.flights"
                )
                Divider().frame(height: 32)
                statColumn(
                    value: selectedStays.count.formatted(),
                    label: "flighty.summary.trips"
                )
                Divider().frame(height: 32)
                statColumn(
                    value: "+\(newCountriesCount.formatted())",
                    label: "flighty.summary.newCountries",
                    tint: newCountriesCount > 0 ? .accentColor : .primary
                )
            }
            .padding(.vertical, 4)
        } footer: {
            if let note = ignoredRowsFootnote {
                Text(verbatim: note)
            }
        }
    }

    private var baseCountriesSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                baseCountryChips
                    .padding(.vertical, 2)
            }
        } header: {
            Text("flighty.base.header")
        } footer: {
            Text("flighty.base.footer")
        }
    }

    @ViewBuilder
    private var baseCountryChips: some View {
        let sortedExcluded = excludedBaseCountries.sorted { lhs, rhs in
            countryDisplayName(lhs).localizedStandardCompare(countryDisplayName(rhs)) == .orderedAscending
        }
        let suggestions = suggestedBaseCountries

        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(sortedExcluded, id: \.self) { code in
                        excludedChipButton(code: code, useGlass: true)
                    }
                    ForEach(suggestions, id: \.self) { code in
                        suggestionChipButton(code: code, useGlass: true)
                    }
                    addBaseCountryButton(useGlass: true)
                }
            }
        } else {
            HStack(spacing: 8) {
                ForEach(sortedExcluded, id: \.self) { code in
                    excludedChipButton(code: code, useGlass: false)
                }
                ForEach(suggestions, id: \.self) { code in
                    suggestionChipButton(code: code, useGlass: false)
                }
                addBaseCountryButton(useGlass: false)
            }
        }
    }

    private func excludedChipButton(code: String, useGlass: Bool) -> some View {
        Button {
            withAnimation(.snappy) {
                _ = excludedBaseCountries.remove(code)
            }
        } label: {
            HStack(spacing: 6) {
                Text(countryFlag(code))
                Text(countryDisplayName(code))
                    .font(.subheadline.weight(.medium))
                Image(systemName: "xmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Capsule())
            .modifier(LiquidChipModifier(isActive: true, useGlass: useGlass))
        }
        .buttonStyle(.plain)
    }

    private func suggestionChipButton(code: String, useGlass: Bool) -> some View {
        Button {
            withAnimation(.snappy) {
                _ = excludedBaseCountries.insert(code)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(countryFlag(code))
                Text(countryDisplayName(code))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Capsule())
            .modifier(LiquidChipModifier(isActive: false, useGlass: useGlass))
        }
        .buttonStyle(.plain)
    }

    private func addBaseCountryButton(useGlass: Bool) -> some View {
        Button {
            showBaseCountryPicker = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.caption.weight(.semibold))
                Text("flighty.base.add")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Capsule())
            .modifier(LiquidChipModifier(isActive: false, useGlass: useGlass))
        }
        .buttonStyle(.plain)
    }

    private var rulesSection: some View {
        Section("flighty.rules.header") {
            Picker("flighty.transit.label", selection: $transitPolicy) {
                Text("flighty.transit.skip").tag(FlightyTransitPolicy.skip)
                Text("flighty.transit.include").tag(FlightyTransitPolicy.includeAsTransit)
            }
            Picker("flighty.granularity.label", selection: $granularity) {
                Text("flighty.granularity.allTrips").tag(FlightyImportGranularity.allTrips)
                Text("flighty.granularity.newCountries").tag(FlightyImportGranularity.newCountriesOnly)
            }
        }
    }

    private var unknownAirportsSection: some View {
        Section {
            ForEach(unknownAirports) { item in
                Button {
                    resolvingAirport = item
                } label: {
                    HStack(spacing: 12) {
                        Text(verbatim: item.iata)
                            .font(.subheadline.monospaced().weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: item.sampleRoute)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Text(String(
                                format: String(localized: "flighty.unknown.flightCount"),
                                locale: .current,
                                item.flightCount
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("flighty.unknown.assign")
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Label("flighty.unknown.header", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } footer: {
            Text("flighty.unknown.footer")
        }
    }

    private var tripsSection: some View {
        Section {
            if activeStays.isEmpty {
                Text("flighty.trips.empty")
                    .foregroundStyle(.secondary)
            } else if groupingMode == .byCountry {
                ForEach(countryGroups) { group in
                    countryGroupHeader(group)
                    ForEach(group.stays) { stay in
                        stayRow(stay, showCountryTitle: false, skipReason: nil)
                            .padding(.leading, 8)
                    }
                }
            } else {
                ForEach(activeStaysSortedNewestFirst) { stay in
                    stayRow(stay, showCountryTitle: true, skipReason: nil)
                }
            }
        } header: {
            HStack {
                Text("flighty.trips.header")
                Spacer()
                if !activeStays.isEmpty {
                    Picker("flighty.viewMode", selection: $groupingMode) {
                        Text("flighty.viewMode.byCountry").tag(GroupingMode.byCountry)
                        Text("flighty.viewMode.timeline").tag(GroupingMode.timeline)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .fixedSize()
                }
            }
            .textCase(nil)
        } footer: {
            if !activeStays.isEmpty {
                Text("flighty.trips.footer")
            }
        }
    }

    private var skippedSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showSkipped) {
                ForEach(skippedEntries, id: \.stay.id) { entry in
                    stayRow(entry.stay, showCountryTitle: true, skipReason: entry.reason)
                }
            } label: {
                HStack {
                    Text("flighty.skipped.header")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(skippedEntries.count.formatted())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("flighty.skipped.footer")
        }
    }

    // MARK: - Row Builders

    private func countryGroupHeader(_ group: CountryGroup) -> some View {
        let allChecked = group.stays.allSatisfy { isStaySelected($0) }
        let isNewCountry = !appState.visitedCountryCodes.contains(group.countryCode)

        return HStack(spacing: 10) {
            Button {
                withAnimation(.snappy) {
                    let target = !allChecked
                    for stay in group.stays {
                        manualSelection[stay.id] = target
                    }
                }
            } label: {
                Image(systemName: allChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(allChecked ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            Text(countryFlag(group.countryCode))
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(countryDisplayName(group.countryCode))
                        .font(.subheadline.weight(.semibold))
                    if isNewCountry {
                        newCountryBadge
                    }
                }
                Text(String(
                    format: String(localized: "flighty.group.subtitle"),
                    locale: .current,
                    group.stays.count,
                    group.totalDays
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func stayRow(_ stay: FlightyStayItem, showCountryTitle: Bool, skipReason: FlightySkipReason?) -> some View {
        let checked = isStaySelected(stay)
        let effectivePurpose = stay.effectivePurpose(transitPolicy: transitPolicy)
        let isNewCountry = !appState.visitedCountryCodes.contains(stay.countryCode)
        let peers = nonBaseStays.filter { $0.countryCode == stay.countryCode && $0.id != stay.id }

        return HStack(spacing: 10) {
            Button {
                withAnimation(.snappy) {
                    manualSelection[stay.id] = !checked
                }
            } label: {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(checked ? Color.accentColor : .secondary)
                    .frame(minWidth: 28, minHeight: 28)
            }
            .buttonStyle(.plain)

            Button {
                editingStay = stay
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        if showCountryTitle {
                            HStack(spacing: 6) {
                                Text(countryFlag(stay.countryCode))
                                Text(countryDisplayName(stay.countryCode))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if isNewCountry {
                                    newCountryBadge
                                }
                            }
                        }

                        HStack(spacing: 6) {
                            Text(dateRangeLabel(for: stay))
                                .font(showCountryTitle ? .caption : .subheadline)
                                .foregroundStyle(showCountryTitle ? .secondary : .primary)

                            Text(String(
                                format: String(localized: "flighty.stay.daysShort"),
                                locale: .current,
                                stay.dayCount
                            ))
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                            .foregroundStyle(.secondary)

                            if effectivePurpose != .leisure {
                                HStack(spacing: 3) {
                                    Image(systemName: effectivePurpose.systemImage)
                                    Text(effectivePurpose.localizedDisplayName)
                                }
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(effectivePurpose.color)
                            }
                        }

                        if !stay.locationText.isEmpty {
                            Text(verbatim: stay.locationText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if let skipReason {
                            Text(skipReasonLabel(skipReason))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        } else if stay.isOpenJaw {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text("flighty.openJaw.badge")
                            }
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                        }
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .opacity(checked ? 1.0 : 0.68)
        .contextMenu {
            Button {
                editingStay = stay
            } label: {
                Label("flighty.action.edit", systemImage: "pencil")
            }

            if stay.canSplitFlights {
                Button {
                    splitStay(stay)
                } label: {
                    Label("flighty.action.split", systemImage: "arrow.branch")
                }
            }

            if !peers.isEmpty {
                Menu {
                    ForEach(peers) { peer in
                        Button(dateRangeLabel(for: peer)) {
                            mergeStays(stay, peer)
                        }
                    }
                } label: {
                    Label("flighty.action.mergeWith", systemImage: "arrow.triangle.merge")
                }
            }
        }
    }

    private var newCountryBadge: some View {
        Text("flighty.badge.new")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .foregroundStyle(Color.accentColor)
    }

    private func statColumn(value: String, label: LocalizedStringKey, tint: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Computed Filtering & Grouping

    private var nonBaseStays: [FlightyStayItem] {
        stays.filter { !excludedBaseCountries.contains($0.countryCode) }
    }

    /// Chosen representative stay ID per country when `granularity == .newCountriesOnly`.
    private var representativeNewCountryStayIDs: Set<UUID> {
        guard granularity == .newCountriesOnly else { return [] }
        var latestByCountry: [String: FlightyStayItem] = [:]
        for stay in nonBaseStays {
            guard !appState.visitedCountryCodes.contains(stay.countryCode) else { continue }
            if stay.isShortTransit && transitPolicy == .skip { continue }
            if let existing = latestByCountry[stay.countryCode] {
                if stay.startDay >= existing.startDay {
                    latestByCountry[stay.countryCode] = stay
                }
            } else {
                latestByCountry[stay.countryCode] = stay
            }
        }
        return Set(latestByCountry.values.map(\.id))
    }

    private func defaultSkipReason(for stay: FlightyStayItem) -> FlightySkipReason? {
        if stay.isShortTransit && transitPolicy == .skip {
            return .transit(minutes: stay.transitMinutes)
        }
        if FlightyImportEngine.matchesExistingVisit(stay, existingVisits: appState.data.visits) {
            return .alreadyLogged
        }
        if granularity == .newCountriesOnly && !representativeNewCountryStayIDs.contains(stay.id) {
            return .alreadyVisitedCountry
        }
        return nil
    }

    private func isStaySelected(_ stay: FlightyStayItem) -> Bool {
        if let manual = manualSelection[stay.id] {
            return manual
        }
        return defaultSkipReason(for: stay) == nil
    }

    /// Stays shown in the main Trips section (either naturally eligible or manually rescued by the user).
    private var activeStays: [FlightyStayItem] {
        nonBaseStays.filter { stay in
            defaultSkipReason(for: stay) == nil || manualSelection[stay.id] == true
        }
    }

    private var activeStaysSortedNewestFirst: [FlightyStayItem] {
        activeStays.sorted { lhs, rhs in
            if lhs.startDay != rhs.startDay { return lhs.startDay > rhs.startDay }
            return lhs.endDay > rhs.endDay
        }
    }

    private var countryGroups: [CountryGroup] {
        let grouped = Dictionary(grouping: activeStaysSortedNewestFirst, by: \.countryCode)
        return grouped
            .map { CountryGroup(countryCode: $0.key, stays: $0.value) }
            .sorted { lhs, rhs in
                let lMax = lhs.stays.first?.startDay ?? FlightyDay(year: 0, month: 1, day: 1)
                let rMax = rhs.stays.first?.startDay ?? FlightyDay(year: 0, month: 1, day: 1)
                if lMax != rMax { return lMax > rMax }
                return countryDisplayName(lhs.countryCode)
                    .localizedStandardCompare(countryDisplayName(rhs.countryCode)) == .orderedAscending
            }
    }

    private var skippedEntries: [(stay: FlightyStayItem, reason: FlightySkipReason)] {
        nonBaseStays.compactMap { stay in
            guard manualSelection[stay.id] != true,
                  let reason = defaultSkipReason(for: stay) else {
                return nil
            }
            return (stay, reason)
        }
        .sorted { $0.stay.startDay > $1.stay.startDay }
    }

    private var selectedStays: [FlightyStayItem] {
        nonBaseStays.filter { isStaySelected($0) }
    }

    private var newCountriesCount: Int {
        let selectedCodes = Set(selectedStays.map(\.countryCode))
        return selectedCodes.subtracting(appState.visitedCountryCodes).count
    }

    private var suggestedBaseCountries: [String] {
        var candidates: [String] = []
        let passport = appState.data.passportCode
        if !passport.isEmpty, !excludedBaseCountries.contains(passport) {
            candidates.append(passport)
        }
        for code in frequentCountryCodes where !excludedBaseCountries.contains(code) && !candidates.contains(code) {
            candidates.append(code)
            if candidates.count >= 3 { break }
        }
        return candidates
    }

    private var ignoredRowsFootnote: String? {
        var parts: [String] = []
        if parsedLog.futureSkipped > 0 {
            parts.append(String(
                format: String(localized: "flighty.ignored.future"),
                locale: .current,
                parsedLog.futureSkipped
            ))
        }
        if parsedLog.canceledSkipped > 0 {
            parts.append(String(
                format: String(localized: "flighty.ignored.canceled"),
                locale: .current,
                parsedLog.canceledSkipped
            ))
        }
        if parsedLog.duplicatesSkipped > 0 {
            parts.append(String(
                format: String(localized: "flighty.ignored.duplicates"),
                locale: .current,
                parsedLog.duplicatesSkipped
            ))
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    // MARK: - Actions & Formatting

    private func initializePreview() {
        switch AirportRepository.catalog {
        case .success(let catalog):
            airports = catalog
            rebuildAnalysis(resetDefaults: true)
        case .failure:
            errorMessage = FlightyImportError.airportCatalogUnavailable.localizedDescription
        }
    }

    private func rebuildAnalysis(resetDefaults: Bool) {
        let analysis = FlightyImportEngine.analyze(
            flights: parsedLog.flights,
            airports: airports,
            airportOverrides: airportOverrides
        )
        stays = analysis.stays
        unknownAirports = analysis.unknownAirports
        frequentCountryCodes = analysis.frequentCountryCodes
        manualSelection.removeAll()

        if resetDefaults {
            if let primary = analysis.detectedPrimaryBase {
                excludedBaseCountries = [primary]
            } else if !appState.data.passportCode.isEmpty {
                excludedBaseCountries = [appState.data.passportCode]
            }
        }
    }

    private func updateStay(_ updated: FlightyStayItem) {
        guard let idx = stays.firstIndex(where: { $0.id == updated.id }) else { return }
        stays[idx] = updated
    }

    private func splitStay(_ stay: FlightyStayItem) {
        guard let idx = stays.firstIndex(where: { $0.id == stay.id }) else { return }
        let pieces = FlightyImportEngine.split(stay, airports: airports, overrides: airportOverrides)
        let wasSelected = isStaySelected(stay)
        withAnimation(.snappy) {
            stays.replaceSubrange(idx...idx, with: pieces)
            manualSelection.removeValue(forKey: stay.id)
            for piece in pieces {
                manualSelection[piece.id] = wasSelected
            }
        }
    }

    private func mergeStays(_ first: FlightyStayItem, _ second: FlightyStayItem) {
        guard let firstIdx = stays.firstIndex(where: { $0.id == first.id }),
              let secondIdx = stays.firstIndex(where: { $0.id == second.id }),
              firstIdx != secondIdx else { return }
        let merged = FlightyImportEngine.merge(first, second)
        let insertIdx = min(firstIdx, secondIdx)
        withAnimation(.snappy) {
            stays.removeAll { $0.id == first.id || $0.id == second.id }
            stays.insert(merged, at: min(insertIdx, stays.count))
            manualSelection.removeValue(forKey: first.id)
            manualSelection.removeValue(forKey: second.id)
            manualSelection[merged.id] = true
        }
    }

    private func commitImport() {
        let toCreate = selectedStays
            .sorted { $0.startDay < $1.startDay }
            .map { $0.toVisit(transitPolicy: transitPolicy) }
        guard !toCreate.isEmpty, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try appState.addVisits(toCreate)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func countryFlag(_ code: String) -> String {
        appState.country(for: code)?.flag ?? "🌍"
    }

    private func countryDisplayName(_ code: String) -> String {
        appState.country(for: code)?.localizedName() ?? code
    }

    private func dateRangeLabel(for stay: FlightyStayItem) -> String {
        let start = stay.startDay.toDate()
        let end = stay.endDay.toDate()
        if stay.startDay == stay.endDay {
            return start.formatted(date: .abbreviated, time: .omitted)
        }
        return TravelFormat.dateRange(start: start, end: end)
    }

    private func skipReasonLabel(_ reason: FlightySkipReason) -> String {
        switch reason {
        case .transit(let minutes):
            if let minutes {
                let hours = minutes / 60
                let mins = minutes % 60
                let durationText = hours > 0
                    ? "\(hours)h \(mins)m"
                    : "\(mins)m"
                return String(
                    format: String(localized: "flighty.skip.transitDuration"),
                    locale: .current,
                    durationText
                )
            }
            return String(localized: "flighty.skip.transit")
        case .alreadyLogged:
            return String(localized: "flighty.skip.alreadyLogged")
        case .alreadyVisitedCountry:
            return String(localized: "flighty.skip.alreadyVisited")
        }
    }
}

// MARK: - Liquid Glass Chip Styling

private struct LiquidChipModifier: ViewModifier {
    let isActive: Bool
    let useGlass: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26, *), useGlass {
            if isActive {
                content.glassEffect(.regular.tint(Color.accentColor.opacity(0.2)).interactive(), in: .capsule)
            } else {
                content.glassEffect(.regular.interactive(), in: .capsule)
            }
        } else {
            content
                .background(
                    isActive ? AnyShapeStyle(Color.accentColor.opacity(0.16)) : AnyShapeStyle(.thinMaterial),
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(isActive ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
    }
}

// MARK: - Inline Stay Editor

private struct FlightyStayEditorSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let stay: FlightyStayItem
    let sameCountryPeers: [FlightyStayItem]
    let onSave: (FlightyStayItem) -> Void
    let onSplit: (() -> Void)?
    let onMerge: (FlightyStayItem) -> Void

    @State private var country: Country?
    @State private var location: String
    @State private var purpose: VisitPurpose
    @State private var startDate: Date?
    @State private var endDate: Date?
    @State private var notes: String
    @State private var showCountryPicker = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case location, notes
    }

    init(
        stay: FlightyStayItem,
        sameCountryPeers: [FlightyStayItem],
        onSave: @escaping (FlightyStayItem) -> Void,
        onSplit: (() -> Void)?,
        onMerge: @escaping (FlightyStayItem) -> Void
    ) {
        self.stay = stay
        self.sameCountryPeers = sameCountryPeers
        self.onSave = onSave
        self.onSplit = onSplit
        self.onMerge = onMerge
        _location = State(initialValue: stay.locationText)
        _purpose = State(initialValue: stay.purpose)
        _startDate = State(initialValue: stay.startDay.toDate())
        _endDate = State(initialValue: stay.endDay.toDate())
        _notes = State(initialValue: stay.notes)
    }

    private var canSave: Bool {
        guard country != nil, let startDate, let endDate else { return false }
        return startDate <= endDate
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionLabel("COUNTRY")
                    Button {
                        focusedField = nil
                        showCountryPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            if let country {
                                Text(country.flag).font(.title2)
                                Text(country.localizedName()).foregroundStyle(.primary)
                            } else {
                                Text(verbatim: stay.countryCode).foregroundStyle(.primary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    sectionLabel("LOCATION (OPTIONAL)")
                    TextField("States / Province / City / Place", text: $location)
                        .focused($focusedField, equals: .location)
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

                    sectionLabel("PURPOSE")
                    VisitPurposePicker(selection: $purpose)

                    sectionLabel("DATES")
                    VStack(spacing: 0) {
                        DateInputRow(
                            title: "Start date",
                            clearLabel: "Clear start date",
                            date: $startDate,
                            range: Date.distantPast...(endDate ?? Date.distantFuture),
                            onPresent: { focusedField = nil }
                        )
                        Divider().padding(.vertical, 6)
                        DateInputRow(
                            title: "End date",
                            clearLabel: "Clear end date",
                            date: $endDate,
                            range: (startDate ?? Date.distantPast)...Date.distantFuture,
                            preferredDate: startDate,
                            onPresent: { focusedField = nil }
                        )
                    }
                    .padding(.vertical, 4)

                    sectionLabel("NOTES")
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .focused($focusedField, equals: .notes)
                        .lineLimit(2...4)
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

                    if !stay.flights.isEmpty {
                        sectionLabel("flighty.editor.flightsHeader")
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(stay.flights) { flight in
                                HStack {
                                    Text(verbatim: flightLabel(flight))
                                        .font(.caption.monospaced())
                                    Spacer()
                                    Text(flight.departure.day.toDate(), format: .dateTime.year().month(.abbreviated).day())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }

                    if onSplit != nil || !sameCountryPeers.isEmpty {
                        VStack(spacing: 10) {
                            if let onSplit {
                                Button {
                                    onSplit()
                                    dismiss()
                                } label: {
                                    Label("flighty.action.split", systemImage: "arrow.branch")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }

                            if !sameCountryPeers.isEmpty {
                                Menu {
                                    ForEach(sameCountryPeers) { peer in
                                        Button(peerLabel(peer)) {
                                            onMerge(peer)
                                            dismiss()
                                        }
                                    }
                                } label: {
                                    Label("flighty.action.mergeWith", systemImage: "arrow.triangle.merge")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit Trip")
            .centeredNavigationTitle("Edit Trip")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveChanges() }
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showCountryPicker) {
                CountryPickerSheet(selected: $country)
            }
            .onAppear {
                if country == nil {
                    country = appState.country(for: stay.countryCode)
                }
            }
        }
    }

    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func flightLabel(_ flight: FlightyFlight) -> String {
        let code = [flight.airline, flight.flightNumber]
            .compactMap { $0 }
            .joined(separator: " ")
        return code.isEmpty ? flight.routeLabel : "\(code) · \(flight.routeLabel)"
    }

    private func peerLabel(_ peer: FlightyStayItem) -> String {
        let dates = TravelFormat.dateRange(start: peer.startDay.toDate(), end: peer.endDay.toDate())
        return peer.locationText.isEmpty ? dates : "\(dates) (\(peer.locationText))"
    }

    private func saveChanges() {
        guard let country, let startDate, let endDate else { return }
        var updated = stay
        updated.countryCode = country.code
        updated.startDay = FlightyDay.from(startDate)
        updated.endDay = FlightyDay.from(endDate)
        updated.purpose = purpose
        updated.notes = notes
        let trimmedLoc = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultLoc = stay.cities.joined(separator: ", ")
        updated.customLocation = (trimmedLoc == defaultLoc) ? nil : trimmedLoc
        onSave(updated)
        dismiss()
    }
}
