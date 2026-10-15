import SwiftUI

struct WishlistStats {
    let countryCount: Int
    let tripCount: Int
    let continentCount: Int
    let totalDays: Int
    let unknownDurationCount: Int
    let flags: [String]

    init(trips: [PlannedTrip], countries: [Country]) {
        let codes = Set(trips.map(\.countryCode))
        countryCount = codes.count
        tripCount = trips.count
        continentCount = Set(codes.compactMap { code in
            Continent.of(code) ?? (["HKG", "MAC"].contains(code) ? .asia : nil)
        }).count
        let durations = trips.compactMap(\.plannedDayCount)
        totalDays = durations.reduce(0) { total, days in
            let result = total.addingReportingOverflow(days)
            return result.overflow ? Int.max : result.partialValue
        }
        unknownDurationCount = trips.count - durations.count
        flags = countries.filter { codes.contains($0.code) }.map(\.flag).sorted()
    }
}

struct WishlistSection: View {
    @EnvironmentObject var appState: AppState
    @State private var showAddTrip = false
    @State private var selectedCountry: Country?

    private var countries: [Country] {
        let codes = Set(appState.data.plannedTrips.map(\.countryCode))
        return appState.countries.filter { codes.contains($0.code) }.sorted {
            $0.localizedName().localizedStandardCompare($1.localizedName()) == .orderedAscending
        }
    }

    var body: some View {
        Button { showAddTrip = true } label: {
            Label("Add to Wishlist", systemImage: "plus.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showAddTrip) {
            PlannedTripEditorSheet(existingTrip: nil, initialCountry: nil)
        }
        .sheet(item: $selectedCountry) { country in
            CountryPlansSheet(country: country)
        }

        if countries.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "heart.text.clipboard")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Your wishlist is empty")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        } else {
            Text("Countries").font(.subheadline.bold()).foregroundStyle(.secondary)
            LazyVStack(spacing: 8) {
                ForEach(countries) { country in
                    Button { selectedCountry = country } label: {
                        countryRow(country)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func countryRow(_ country: Country) -> some View {
        let plans = appState.plannedTrips(for: country.code)
        let places = plans.compactMap(\.location).prefix(2)
        return HStack(spacing: 12) {
            Text(country.flag).font(.title2).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(country.localizedName()).font(.subheadline.weight(.semibold))
                Text("\(plans.count) trips planned")
                    .font(.caption).foregroundStyle(.secondary)
                if !places.isEmpty {
                    Text(Array(places).formatted(.list(type: .and)))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if appState.visitedCountryCodes.contains(country.code) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel(Text("Visited before"))
                    .help(Text("Visited before"))
            }
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

struct WishlistSummaryCard: View {
    let stats: WishlistStats

    var body: some View {
        TravelCompactCard(
            title: "Wishlist", countryCount: stats.countryCount,
            countryLabel: stats.countryCount == 1 ? "country added" : "countries added",
            tripCount: stats.tripCount,
            tripLabel: stats.tripCount == 1 ? "trip planned" : "trips planned",
            flags: stats.flags, continentCount: stats.continentCount,
            days: stats.tripCount > 0 && stats.unknownDurationCount == stats.tripCount
                ? "-" : stats.totalDays.formatted(),
            daysLabel: "Days Planned",
            durationNotice: stats.unknownDurationCount > 0
                ? "\(stats.unknownDurationCount) trips without duration" : nil,
            colors: [Color(red: 0.08, green: 0.34, blue: 0.30),
                     Color(red: 0.08, green: 0.25, blue: 0.34)]
        )
    }
}

struct CountryPlansSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let country: Country

    @State private var showAddTrip = false
    @State private var selection: PlanSelection?
    @State private var showSaveError = false

    private struct PlanSelection: Identifiable {
        let trip: PlannedTrip
        let completing: Bool
        var id: UUID { trip.id }
    }

    private var plans: [PlannedTrip] { appState.plannedTrips(for: country.code) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        Text(country.flag).font(.system(size: 44))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(country.localizedName()).font(.title3.bold())
                            Text("\(plans.count) trips planned").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    Button { showAddTrip = true } label: {
                        Label("Add Planned Trip", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding()
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    ForEach(plans) { plan in planRow(plan) }
                }
                .padding()
            }
            .navigationTitle(country.localizedName())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showAddTrip, onDismiss: dismissIfEmpty) {
                PlannedTripEditorSheet(existingTrip: nil, initialCountry: country)
            }
            .sheet(item: $selection, onDismiss: dismissIfEmpty) { selected in
                if selected.completing {
                    TripEditorSheet(existingVisit: nil, initialCountry: appState.country(for: selected.trip.countryCode),
                                    completingTrip: selected.trip)
                } else {
                    PlannedTripEditorSheet(existingTrip: selected.trip,
                                           initialCountry: appState.country(for: selected.trip.countryCode))
                }
            }
            .alert("Couldn't Save", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your changes weren't saved. Please try again.")
            }
        }
    }

    private func planRow(_ plan: PlannedTrip) -> some View {
        HStack(spacing: 12) {
            Button { selection = PlanSelection(trip: plan, completing: false) } label: {
                HStack(spacing: 12) {
                    Image(systemName: plan.purpose.systemImage)
                        .foregroundStyle(plan.purpose.color).frame(width: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(plan.location ?? country.localizedName()).font(.subheadline.weight(.semibold))
                        Text(WishlistFormat.duration(plan)).font(.caption).foregroundStyle(.secondary)
                        Text(plan.purpose.localizedDisplayName)
                            .font(.caption2.weight(.semibold)).foregroundStyle(plan.purpose.color)
                        if let notes = plan.notes {
                            Text(notes).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Menu {
                Button { selection = PlanSelection(trip: plan, completing: false) } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button { selection = PlanSelection(trip: plan, completing: true) } label: {
                    Label("Mark Completed", systemImage: "checkmark.circle")
                }
                Button(role: .destructive) { delete(plan) } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Trip actions"))
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func delete(_ plan: PlannedTrip) {
        do {
            try appState.removePlannedTrip(plan.id)
            dismissIfEmpty()
        } catch { showSaveError = true }
    }

    private func dismissIfEmpty() {
        if plans.isEmpty { dismiss() }
    }
}

struct PlannedTripEditorSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let existingTrip: PlannedTrip?

    @State private var country: Country?
    @State private var showCountryPicker = false
    @State private var location: String
    @State private var purpose: VisitPurpose
    @State private var notes: String
    @State private var durationMode: PlannedDurationMode
    @State private var estimatedDays: String
    @State private var startDate: Date?
    @State private var endDate: Date?
    @State private var completingTrip: PlannedTrip?
    @State private var showSaveError = false

    init(existingTrip: PlannedTrip?, initialCountry: Country?) {
        self.existingTrip = existingTrip
        _country = State(initialValue: initialCountry)
        _location = State(initialValue: existingTrip?.location ?? "")
        _purpose = State(initialValue: existingTrip?.purpose ?? .leisure)
        _notes = State(initialValue: existingTrip?.notes ?? "")
        _durationMode = State(initialValue: existingTrip?.durationMode ?? .notSet)
        _estimatedDays = State(initialValue: existingTrip?.estimatedDays.map(String.init) ?? "1")
        _startDate = State(initialValue: existingTrip?.startDate)
        _endDate = State(initialValue: existingTrip?.endDate)
    }

    private var canSave: Bool {
        country != nil && (durationMode != .estimatedDays || (Int(estimatedDays) ?? 0) > 0)
    }

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
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    label("LOCATION (OPTIONAL)")
                    TextField("States / Province / City / Place", text: $location)
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

                    label("PURPOSE")
                    VisitPurposePicker(selection: $purpose)

                    label("Duration")
                    Picker("Duration", selection: $durationMode) {
                        Text("Not set").tag(PlannedDurationMode.notSet)
                        Text("Estimate").tag(PlannedDurationMode.estimatedDays)
                        Text("Dates").tag(PlannedDurationMode.dates)
                    }
                    .pickerStyle(.segmented)
                    if durationMode == .estimatedDays {
                        estimatedDaysRow
                        if (Int(estimatedDays) ?? 0) <= 0 {
                            Text("Enter a positive whole number of days.")
                                .font(.caption).foregroundStyle(.red)
                        }
                    } else if durationMode == .dates {
                        VStack(spacing: 0) {
                            DateInputRow(title: "Start date", clearLabel: "Clear start date", date: $startDate,
                                         range: Date.distantPast...(endDate ?? .distantFuture))
                            Divider().padding(.vertical, 6)
                            DateInputRow(title: "End date", clearLabel: "Clear end date", date: $endDate,
                                         range: (startDate ?? .distantPast)...Date.distantFuture, preferredDate: startDate)
                        }
                        .padding(.vertical, 4)
                        if let days = makeTrip()?.plannedDayCount {
                            Text("\(days) days planned").font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    label("NOTES")
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

                    if existingTrip != nil {
                        Button("Mark Completed") {
                            completingTrip = makeTrip()
                        }
                        .disabled(!canSave)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        Button("Delete Planned Trip", role: .destructive) { delete() }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }
                }
                .padding()
            }
            .navigationTitle(existingTrip == nil ? "Add to Wishlist" : "Edit Planned Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Save") { save() }.disabled(!canSave) }
            }
            .sheet(isPresented: $showCountryPicker) { CountryPickerSheet(selected: $country) }
            .sheet(item: $completingTrip, onDismiss: dismissIfCompleted) { plan in
                TripEditorSheet(existingVisit: nil, initialCountry: appState.country(for: plan.countryCode),
                                completingTrip: plan)
            }
            .onChange(of: durationMode) { _, newMode in
                estimatedDays = newMode == .estimatedDays ? "1" : ""
                startDate = nil
                endDate = nil
            }
            .alert("Couldn't Save", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your changes weren't saved. Please try again.")
            }
        }
    }

    private var estimatedDaysRow: some View {
        HStack(spacing: 12) {
            Text("Estimated days")
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            TextField("Estimated days", text: $estimatedDays)
                .keyboardType(.numberPad)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
                .accessibilityLabel(Text("Estimated days"))
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        estimatedDays = String(max(1, (Int(estimatedDays) ?? 1) - 1))
                    } label: {
                        Image(systemName: "minus")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .disabled((Int(estimatedDays) ?? 1) <= 1)
                    .accessibilityLabel(Text("Decrease estimated days"))
                    .help(Text("Decrease estimated days"))

                    Button {
                        let current = Int(estimatedDays) ?? 0
                        if current < Int.max { estimatedDays = String(max(1, current + 1)) }
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .disabled(Int(estimatedDays) == Int.max)
                    .accessibilityLabel(Text("Increase estimated days"))
                    .help(Text("Increase estimated days"))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
        .frame(minHeight: 44)
    }

    private func label(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func makeTrip() -> PlannedTrip? {
        guard let country else { return nil }
        return PlannedTrip(id: existingTrip?.id ?? UUID(), countryCode: country.code,
                           createdAt: existingTrip?.createdAt ?? Date(), location: location,
                           purpose: purpose, notes: notes, durationMode: durationMode,
                           estimatedDays: Int(estimatedDays), startDate: startDate, endDate: endDate)
    }

    private func save() {
        guard canSave, let trip = makeTrip() else { return }
        do {
            if existingTrip == nil { try appState.addPlannedTrip(trip) }
            else { try appState.updatePlannedTrip(trip) }
            dismiss()
        } catch { showSaveError = true }
    }

    private func delete() {
        guard let existingTrip else { return }
        do {
            try appState.removePlannedTrip(existingTrip.id)
            dismiss()
        } catch { showSaveError = true }
    }

    private func dismissIfCompleted() {
        if let existingTrip, !appState.data.plannedTrips.contains(where: { $0.id == existingTrip.id }) {
            dismiss()
        }
    }
}

enum WishlistFormat {
    static func duration(_ trip: PlannedTrip) -> String {
        switch trip.durationMode {
        case .estimatedDays:
            guard let days = trip.plannedDayCount else { return String(localized: "No duration set") }
            return String(localized: "\(days) estimated days")
        case .dates:
            guard trip.startDate != nil || trip.endDate != nil else { return String(localized: "No duration set") }
            return TravelFormat.dateRange(trip.visitDraft)
        case .notSet:
            return String(localized: "No duration set")
        }
    }
}