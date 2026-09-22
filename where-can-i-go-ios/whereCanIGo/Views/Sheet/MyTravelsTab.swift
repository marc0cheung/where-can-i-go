import SwiftUI

// MARK: - My Travels Tab

struct MyTravelsTab: View {
    @EnvironmentObject var appState: AppState

    @State private var showSummary = false
    @State private var showAddTrip = false
    @State private var addTripInitialCountry: Country? = nil
    @State private var countryDetail: Country? = nil

    /// Visited countries grouped with their visits, most-recent country first.
    private var visitedGroups: [(country: Country, visits: [Visit])] {
        appState.visitedCountryCodes.compactMap { code -> (Country, [Visit])? in
            guard let country = appState.country(for: code) else { return nil }
            return (country, appState.visits(for: code))
        }
        .sorted { lhs, rhs in
            let l = lhs.1.first?.startDate ?? .distantPast
            let r = rhs.1.first?.startDate ?? .distantPast
            if l == r { return lhs.0.localizedName() < rhs.0.localizedName() }
            return l > r
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Where I've Been").font(.headline)

                Button { showSummary = true } label: {
                    TravelSummaryCard(stats: TravelStats(appState: appState))
                }
                .buttonStyle(.plain)

                Button {
                    addTripInitialCountry = nil
                    showAddTrip = true
                } label: {
                    Label("Log a Visit", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                if visitedGroups.isEmpty {
                    emptyState
                } else {
                    Text("Countries")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)

                    LazyVStack(spacing: 8) {
                        ForEach(visitedGroups, id: \.country.id) { group in
                            Button { countryDetail = group.country } label: {
                                countryRow(group.country, visits: group.visits)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding()
        }
        .sheet(isPresented: $showSummary) { TravelSummaryView() }
        .sheet(isPresented: $showAddTrip) {
            TripEditorSheet(existingVisit: nil, initialCountry: addTripInitialCountry)
        }
        .sheet(item: $countryDetail) { country in
            CountryTripsSheet(country: country)
        }
        .onChange(of: appState.pendingAddVisitCountryCode) { _, newCode in
            handlePendingVisit(newCode)
        }
        .onAppear { handlePendingVisit(appState.pendingAddVisitCountryCode) }
    }

    private func handlePendingVisit(_ code: String?) {
        guard let code, let country = appState.country(for: code) else { return }
        appState.pendingAddVisitCountryCode = nil
        addTripInitialCountry = country
        showAddTrip = true
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "airplane.departure")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No countries logged yet")
                .font(.subheadline.weight(.semibold))
            Text("Tap “Log a Visit” to add a country you’ve been to.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func countryRow(_ country: Country, visits: [Visit]) -> some View {
        let tripNoun = visits.count == 1 ? String(localized: "trip") : String(localized: "trips")
        return HStack(spacing: 12) {
            Text(country.flag).font(.title2).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(country.localizedName()).font(.subheadline.weight(.semibold))
                Text(rowSubtitle(for: visits))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("\(visits.count) \(tripNoun)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial, in: Capsule())
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func rowSubtitle(for visits: [Visit]) -> String {
        guard let latest = visits.first else { return String(localized: "No dates") }
        return TravelFormat.dateRange(latest)
    }
}

// MARK: - Travel Stats

struct TravelStats {
    let countryCount: Int
    let tripCount: Int
    let continentCount: Int
    let totalDays: Int
    let flags: [String]
    let continents: [Continent]
    let firstTrip: Date?
    let lastTrip: Date?
    let visitedCodes: Set<String>

    init(appState: AppState) {
        let visits = appState.data.visits
        let codes = Set(visits.map { $0.countryCode })
        countryCount = codes.count
        tripCount = visits.count
        totalDays = visits.compactMap { $0.dayCount }.reduce(0, +)

        let contSet = Set(codes.compactMap { Continent.of($0) })
        continents = Continent.allCases.filter { contSet.contains($0) }
        continentCount = contSet.count

        let starts = visits.compactMap { $0.startDate }
        firstTrip = starts.min()
        lastTrip = starts.max()

        flags = codes.compactMap { appState.country(for: $0)?.flag }.sorted()
        visitedCodes = codes
    }
}

// MARK: - Compact Summary Card

struct TravelSummaryCard: View {
    let stats: TravelStats

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ALL-TIME TRAVELS")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("\(stats.countryCount)")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.white)
                    Text(stats.countryCount == 1 ? "country visited" : "countries visited")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }

            if !stats.flags.isEmpty {
                HStack(spacing: 2) {
                    ForEach(Array(stats.flags.prefix(12)), id: \.self) { flag in
                        Text(flag).font(.body)
                    }
                    if stats.flags.count > 12 {
                        Text("+\(stats.flags.count - 12)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }

            HStack(spacing: 0) {
                miniStat("\(stats.tripCount)", "Trips")
                Divider().frame(height: 28).overlay(.white.opacity(0.25))
                miniStat("\(stats.continentCount)", "Continents")
                Divider().frame(height: 28).overlay(.white.opacity(0.25))
                miniStat("\(stats.totalDays)", "Days")
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color(red: 0.18, green: 0.14, blue: 0.45),
                         Color(red: 0.10, green: 0.16, blue: 0.42)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    private func miniStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.weight(.bold)).foregroundStyle(.white)
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Full-Page Summary + Share

struct TravelSummaryView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TravelPassportCard(stats: TravelStats(appState: appState))
                        .frame(maxWidth: 400)
                }
                .padding()
            }
            .navigationTitle("Where I've Been")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let image = shareImage() {
                        ShareLink(
                            item: image,
                            preview: SharePreview("Where I've Been", image: image)
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }

    /// Renders the passport card off-screen to a shareable image.
    @MainActor private func shareImage() -> Image? {
        let renderer = ImageRenderer(
            content: TravelPassportCard(stats: TravelStats(appState: appState))
                .frame(width: 380)
                .padding(20)
                .background(Color(.systemBackground))
        )
        renderer.scale = displayScale
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
    }
}

// MARK: - Exportable Passport Card

struct TravelPassportCard: View {
    let stats: TravelStats

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WorldMapView(visitedCodes: stats.visitedCodes)
                .padding(.horizontal, 4)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text("WHERE I'VE BEEN")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
                Text("\(stats.countryCount)")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(.white)
                Text(stats.countryCount == 1 ? "country" : "countries")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }

            if !stats.flags.isEmpty {
                FlagWrap(flags: Array(stats.flags.prefix(30)))
            }

            HStack(spacing: 12) {
                statBlock("\(stats.tripCount)", "Trips")
                statBlock("\(stats.continentCount)", "Continents")
                statBlock("\(stats.totalDays)", "Days")
            }

            if let first = stats.firstTrip {
                HStack(spacing: 16) {
                    labeledDate("First trip", first)
                    if let last = stats.lastTrip {
                        labeledDate("Latest trip", last)
                    }
                }
            }

            Text("Tracked with Where Can I Go?")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(red: 0.20, green: 0.15, blue: 0.50),
                         Color(red: 0.08, green: 0.13, blue: 0.38)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private func statBlock(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.bold)).foregroundStyle(.white)
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labeledDate(_ label: String, _ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text(date.formatted(date: .abbreviated, time: .omitted))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
    }
}

/// Simple wrapping row of flag emoji that renders reliably in ImageRenderer.
private struct FlagWrap: View {
    let flags: [String]

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 26), spacing: 4)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
            ForEach(Array(flags.enumerated()), id: \.offset) { _, flag in
                Text(flag).font(.title3)
            }
        }
    }
}

// MARK: - Country Trips Sheet (view / edit / remove)

struct CountryTripsSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let country: Country

    @State private var editingVisit: Visit? = nil
    @State private var showAddTrip = false

    private var visits: [Visit] { appState.visits(for: country.code) }
    private var totalDays: Int { visits.compactMap { $0.dayCount }.reduce(0, +) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    Button { showAddTrip = true } label: {
                        Label("Add Another Visit", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    ForEach(visits) { visit in
                        visitRow(visit)
                    }
                }
                .padding()
            }
            .navigationTitle(country.localizedName())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showAddTrip) {
                TripEditorSheet(existingVisit: nil, initialCountry: country)
            }
            .sheet(item: $editingVisit) { visit in
                TripEditorSheet(existingVisit: visit, initialCountry: country)
            }
            .onChange(of: appState.data.visits) { _, _ in
                if visits.isEmpty { dismiss() }
            }
        }
    }

    private var header: some View {
        let tripNoun = visits.count == 1 ? String(localized: "trip") : String(localized: "trips")
        let dayNoun = totalDays == 1 ? String(localized: "day") : String(localized: "days")
        return HStack(spacing: 14) {
            Text(country.flag).font(.system(size: 44))
            VStack(alignment: .leading, spacing: 2) {
                Text(country.localizedName()).font(.title3.bold())
                Text("\(visits.count) \(tripNoun) · \(totalDays) \(dayNoun)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func visitRow(_ visit: Visit) -> some View {
        Button { editingVisit = visit } label: {
            HStack(spacing: 12) {
                Image(systemName: visit.purpose.systemImage)
                    .foregroundStyle(visit.purpose.color)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(TravelFormat.dateRange(visit))
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 6) {
                        Text(visit.purpose.localizedDisplayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(visit.purpose.color)
                        if let days = visit.dayCount {
                            Text("· \(days) \(days == 1 ? String(localized: "day") : String(localized: "days"))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let notes = visit.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Menu {
                    Button { editingVisit = visit } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        appState.removeVisit(visit.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Trip Editor Sheet (add / edit)

struct TripEditorSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let existingVisit: Visit?

    @State private var country: Country?
    @State private var showCountryPicker = false
    @State private var hasStart: Bool
    @State private var startDate: Date
    @State private var hasEnd: Bool
    @State private var endDate: Date
    @State private var purpose: VisitPurpose
    @State private var notes: String

    init(existingVisit: Visit?, initialCountry: Country?) {
        self.existingVisit = existingVisit
        _country = State(initialValue: initialCountry)
        _hasStart = State(initialValue: existingVisit?.startDate != nil)
        _startDate = State(initialValue: existingVisit?.startDate ?? Date())
        _hasEnd = State(initialValue: existingVisit?.endDate != nil)
        _endDate = State(initialValue: existingVisit?.endDate ?? Date())
        _purpose = State(initialValue: existingVisit?.purpose ?? .leisure)
        _notes = State(initialValue: existingVisit?.notes ?? "")
    }

    private var canSave: Bool { country != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    label("COUNTRY")
                    Button { showCountryPicker = true } label: {
                        HStack(spacing: 12) {
                            if let country {
                                Text(country.flag).font(.title2)
                                Text(country.localizedName()).foregroundStyle(.primary)
                            } else {
                                Text("Select a country").foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    label("PURPOSE")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(VisitPurpose.allCases) { p in
                                purposeChip(p)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    label("DATES")
                    VStack(spacing: 0) {
                        Toggle(isOn: $hasStart.animation()) {
                            Text("Start date")
                        }
                        .padding(.vertical, 4)
                        if hasStart {
                            DatePicker("Start", selection: $startDate, displayedComponents: .date)
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Divider().padding(.vertical, 6)
                        Toggle(isOn: $hasEnd.animation()) {
                            Text("End date")
                        }
                        .padding(.vertical, 4)
                        if hasEnd {
                            DatePicker(
                                "End",
                                selection: $endDate,
                                in: (hasStart ? startDate : Date.distantPast)...,
                                displayedComponents: .date
                            )
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

                    label("NOTES")
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

                    if existingVisit != nil {
                        Button("Delete Visit", role: .destructive) {
                            if let existingVisit { appState.removeVisit(existingVisit.id) }
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                    }
                }
                .padding()
            }
            .navigationTitle(existingVisit == nil ? "Log a Visit" : "Edit Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
            .sheet(isPresented: $showCountryPicker) {
                CountryPickerSheet(selected: $country)
            }
        }
    }

    private func purposeChip(_ p: VisitPurpose) -> some View {
        let selected = purpose == p
        return Button { purpose = p } label: {
            Label(p.localizedDisplayName, systemImage: p.systemImage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? p.color : .secondary)
                .background(
                    Capsule().fill(selected ? p.color.opacity(0.18) : Color(.systemGray6))
                )
                .overlay(
                    Capsule().stroke(selected ? p.color : .clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func label(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func save() {
        guard let country else { return }
        let visit = Visit(
            id: existingVisit?.id ?? UUID(),
            countryCode: country.code,
            startDate: hasStart ? Calendar.current.startOfDay(for: startDate) : nil,
            endDate: hasEnd ? Calendar.current.startOfDay(for: endDate) : nil,
            purpose: purpose,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        )
        if existingVisit == nil {
            appState.addVisit(visit)
        } else {
            appState.updateVisit(visit)
        }
        dismiss()
    }
}

// MARK: - Formatting

enum TravelFormat {
    static func dateRange(_ visit: Visit) -> String {
        switch (visit.startDate, visit.endDate) {
        case let (start?, end?):
            return "\(short(start)) – \(short(end))"
        case let (start?, nil):
            return short(start)
        case let (nil, end?):
            return String(localized: "Until \(short(end))")
        default:
            return String(localized: "No dates set")
        }
    }

    private static func short(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}
