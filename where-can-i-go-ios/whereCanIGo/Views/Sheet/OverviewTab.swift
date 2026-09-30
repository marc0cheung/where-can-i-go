import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct OverviewTab: View {
    @EnvironmentObject var appState: AppState
    @State private var search: String = ""
    @State private var isCompactHeight = false
    @State private var countryBeingEdited: Country? = nil
    @State private var confirmReset = false
    @State private var selectedCategories: Set<VisaCategory> = []
    @State private var selectedContinents: Set<Continent> = []
    @State private var selectedVisitStatuses: Set<OverviewVisitStatus> = []

    private var counts: (vf: Int, voa: Int, eta: Int, mine: Int, total: Int) {
        let vf = appState.data.defaultVisas.filter { $0.category == .visaFree }.count
        let voa = appState.data.defaultVisas.filter { $0.category == .visaOnArrival }.count
        let eta = appState.data.defaultVisas.filter { $0.category == .eta }.count
        let mine = appState.data.personalVisas.count
        return (vf, voa, eta, mine, vf + voa + eta + mine)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    if isCompactHeight {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                categoryStat(value: counts.vf, label: "Visa Free", category: .visaFree)
                                categoryStat(value: counts.voa, label: "Visa on Arrival", category: .visaOnArrival)
                                categoryStat(value: counts.eta, label: "ETA", category: .eta)
                                categoryStat(value: counts.mine, label: "My Visas", category: .myVisa)
                                accessibleStat()
                            }
                            .padding(.horizontal)
                            .padding(.vertical)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                    } else {
                        VStack(spacing: 10) {
                            HStack(spacing: 10) {
                                categoryStat(value: counts.vf, label: "Visa Free", category: .visaFree, width: .flexible)
                                categoryStat(value: counts.voa, label: "Visa on Arrival", category: .visaOnArrival, width: .flexible)
                                categoryStat(value: counts.eta, label: "ETA", category: .eta, width: .flexible)
                            }
                            HStack(spacing: 10) {
                                categoryStat(value: counts.mine, label: "My Visas", category: .myVisa, width: .flexible)
                                accessibleStat(width: .flexible)
                            }
                        }
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                    }

                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search countries…", text: $search)
                            .autocorrectionDisabled()
                        if !search.isEmpty {
                            Button { search = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)

                    filterControls

                    let countries = filteredCountries
                    if hasActiveFilters || !search.isEmpty {
                        Text("Countries: \(countries.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }

                    LazyVStack(spacing: 8) {
                        ForEach(countries) { country in
                            Button {
                                countryBeingEdited = country
                            } label: {
                                CountryRow(country: country)
                            }
                            .buttonStyle(.plain)
                        }

                        if countries.isEmpty {
                            ContentUnavailableView {
                                Label("No Matching Countries", systemImage: "magnifyingglass")
                            } actions: {
                                Button {
                                    search = ""
                                    clearFilters()
                                } label: {
                                    Label("Clear Search and Filters", systemImage: "arrow.counterclockwise")
                                        .font(.subheadline.weight(.semibold))
                                        .multilineTextAlignment(.center)
                                }
                                .buttonStyle(.glassProminent)
                                .tint(.blue)
                                .controlSize(.regular)
                                .padding(.top, 12)
                            }
                        }

                        if search.isEmpty && !hasActiveFilters {
                            Button {
                                confirmReset = true
                            } label: {
                                Text("RESET TO DEFAULT DATA")
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .foregroundStyle(.primary)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .padding(.top, 8)
                            .confirmationDialog(
                                "Reset to bundled defaults? Your custom edits will be lost.",
                                isPresented: $confirmReset,
                                titleVisibility: .visible
                            ) {
                                Button("Reset", role: .destructive) { appState.resetDefaultsToBundled() }
                                Button("Cancel", role: .cancel) {}
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .padding(.top, 12)
            }
            .onAppear {
                isCompactHeight = proxy.size.height < 430
            }
            .onChange(of: proxy.size.height) { _, newHeight in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isCompactHeight = newHeight < 430
                }
            }
            .sheet(item: $countryBeingEdited) { country in
                EntryPolicySheet(
                    country: country,
                    existingEntry: appState.data.defaultVisas.first { $0.countryCode == country.code },
                    existingPersonalVisa: appState.data.personalVisas.first { $0.countryCode == country.code }
                )
            }
        }
    }

    private var hasActiveFilters: Bool {
        !selectedCategories.isEmpty || !selectedContinents.isEmpty || !selectedVisitStatuses.isEmpty
    }

    private var accessibleCategories: Set<VisaCategory> {
        [.visaFree, .visaOnArrival, .eta, .myVisa]
    }

    private var filterControls: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: hasActiveFilters ? 8 : 12) {
                Menu {
                    Toggle("All Entry Requirements", isOn: allSelectionBinding($selectedCategories))
                    Divider()
                    ForEach(VisaCategory.allCases, id: \.self) { category in
                        Toggle(category == .myVisa ? String(localized: "My Visas") : category.localizedDisplayName,
                               isOn: selectionBinding(category, in: $selectedCategories))
                    }
                } label: {
                    filterLabel("Entry", systemImage: "doc.text", count: selectedCategories.count)
                }
                .accessibilityLabel("Entry Requirement")
                .frame(maxWidth: .infinity)
                .accessibilityValue(selectedCategories.isEmpty ? String(localized: "All Entry Requirements") : selectedCategories.sorted { $0.rawValue < $1.rawValue }.map(\.localizedDisplayName).joined(separator: ", "))
                .tint(selectedCategories.isEmpty ? Color.primary : Color.accentColor)

                Menu {
                    Toggle("All Continents", isOn: allSelectionBinding($selectedContinents))
                    Divider()
                    ForEach(Continent.allCases, id: \.self) { continent in
                        Toggle(continentTitle(continent), isOn: selectionBinding(continent, in: $selectedContinents))
                    }
                } label: {
                    filterLabel("Continent", systemImage: "globe", count: selectedContinents.count)
                }
                .frame(maxWidth: .infinity)
                .accessibilityValue(selectedContinents.isEmpty ? String(localized: "All Continents") : selectedContinents.sorted { $0.rawValue < $1.rawValue }.map(continentTitle).joined(separator: ", "))
                .tint(selectedContinents.isEmpty ? Color.primary : Color.accentColor)

                Menu {
                    Toggle("All Visit Statuses", isOn: allSelectionBinding($selectedVisitStatuses))
                    Divider()
                    ForEach(OverviewVisitStatus.allCases, id: \.self) { visitStatus in
                        Toggle(visitStatus.localizedTitle, isOn: selectionBinding(visitStatus, in: $selectedVisitStatuses))
                    }
                } label: {
                    filterLabel("Visited", systemImage: "mappin.and.ellipse", count: selectedVisitStatuses.count)
                }
                .accessibilityLabel("Visited Status")
                .frame(maxWidth: .infinity)
                .accessibilityValue(selectedVisitStatuses.isEmpty ? String(localized: "All Visit Statuses") : selectedVisitStatuses.sorted { $0.rawValue < $1.rawValue }.map(\.localizedTitle).joined(separator: ", "))
                .tint(selectedVisitStatuses.isEmpty ? Color.primary : Color.accentColor)

                if hasActiveFilters {
                    Button(action: clearFilters) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                            .glassEffect(.clear.interactive(), in: .circle)
                    }
                    .accessibilityLabel("Clear Filters")
                    .help("Clear Filters")
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .buttonStyle(.plain)
            .menuActionDismissBehavior(.disabled)
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
        .animation(.smooth(duration: 0.2), value: hasActiveFilters)
    }

    private func filterLabel(_ title: LocalizedStringKey, systemImage: String, count: Int) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                Text(title)
                if count > 0 {
                    Text(count, format: .number)
                        .monospacedDigit()
                        .transition(.identity)
                }
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .fixedSize()

            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .fixedSize()
                Text(title)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if count > 0 {
                    Text(count, format: .number)
                        .monospacedDigit()
                        .fixedSize()
                        .transition(.identity)
                }
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Capsule())
        .glassEffect(.clear.interactive(), in: .capsule)
    }

    private func allSelectionBinding<Value: Hashable>(_ selection: Binding<Set<Value>>) -> Binding<Bool> {
        Binding {
            selection.wrappedValue.isEmpty
        } set: { _ in
            selection.wrappedValue.removeAll()
        }
    }

    private func selectionBinding<Value: Hashable>(_ value: Value, in selection: Binding<Set<Value>>) -> Binding<Bool> {
        Binding {
            selection.wrappedValue.contains(value)
        } set: { isSelected in
            if isSelected {
                selection.wrappedValue.insert(value)
            } else {
                selection.wrappedValue.remove(value)
            }
        }
    }

    private func categoryStat(value: Int, label: LocalizedStringResource, category: VisaCategory, width: StatCard.WidthMode = .fixed(152)) -> some View {
        let selection = selectionBinding(category, in: $selectedCategories)
        return Button {
            selection.wrappedValue.toggle()
        } label: {
            StatCard(value: value, label: label, color: category.color, width: width, isSelected: selection.wrappedValue)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection.wrappedValue ? .isSelected : [])
    }

    private func accessibleStat(width: StatCard.WidthMode = .fixed(152)) -> some View {
        let isSelected = selectedCategories == accessibleCategories
        return Button {
            selectedCategories = isSelected ? [] : accessibleCategories
        } label: {
            StatCard(value: counts.total, label: "Total Accessible", color: .primary, width: width, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func clearFilters() {
        selectedCategories.removeAll()
        selectedContinents.removeAll()
        selectedVisitStatuses.removeAll()
    }

    private func continentTitle(_ continent: Continent) -> String {
        switch continent {
        case .africa: String(localized: "Africa")
        case .asia: String(localized: "Asia")
        case .europe: String(localized: "Europe")
        case .northAmerica: String(localized: "North America")
        case .southAmerica: String(localized: "South America")
        case .oceania: String(localized: "Oceania")
        }
    }

    private var filteredCountries: [Country] {
        let visitedCodes = appState.visitedCountryCodes
        return appState.countries.filter { country in
            let matchesSearch = search.isEmpty ||
                country.localizedName().localizedCaseInsensitiveContains(search) ||
                country.name.localizedCaseInsensitiveContains(search)
            let matchesCategory = selectedCategories.isEmpty ||
                selectedCategories.contains(appState.visaCategory(for: country.code))
            let continent = Continent.of(country.code) ?? (["HKG", "MAC"].contains(country.code) ? .asia : nil)
            let matchesContinent = selectedContinents.isEmpty ||
                continent.map { selectedContinents.contains($0) } == true
            let visitStatus: OverviewVisitStatus = visitedCodes.contains(country.code) ? .visited : .notVisited
            let matchesVisitStatus = selectedVisitStatuses.isEmpty || selectedVisitStatuses.contains(visitStatus)
            return matchesSearch && matchesCategory && matchesContinent && matchesVisitStatus
        }
    }
}

private enum OverviewVisitStatus: String, CaseIterable {
    case visited
    case notVisited

    var localizedTitle: String {
        switch self {
        case .visited: String(localized: "Visited")
        case .notVisited: String(localized: "Not Visited")
        }
    }
}

private struct StatCard: View {
    enum WidthMode {
        case fixed(CGFloat)
        case flexible
    }

    let value: Int
    let label: LocalizedStringResource
    let color: Color
    var width: WidthMode = .fixed(152)
    var isSelected = false

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.system(size: 32, weight: .bold))
            Text(String(localized: label).uppercased(with: .current))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: isFlexible ? .infinity : nil)
        .frame(width: fixedWidth)
        .padding(.vertical, 16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .background(isSelected ? color.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color, lineWidth: isSelected ? 2 : 1)
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(color)
                    .padding(6)
            }
        }
    }

    private var isFlexible: Bool {
        switch width {
        case .fixed: return false
        case .flexible: return true
        }
    }

    private var fixedWidth: CGFloat? {
        switch width {
        case .fixed(let value): return value
        case .flexible: return nil
        }
    }
}

private struct CountryRow: View {
    @EnvironmentObject var appState: AppState
    let country: Country

    private var category: VisaCategory { appState.visaCategory(for: country.code) }

    private var subtitleText: String {
        if let p = appState.data.personalVisas.first(where: { $0.countryCode == country.code }) {
            let expiry = String(localized: "Expires \(p.expiryDate.formatted(date: .abbreviated, time: .omitted))")
            return "\(p.visaType) · \(p.duration) · \(expiry)"
        }
        if let d = appState.data.defaultVisas.first(where: { $0.countryCode == country.code }) {
            if let dur = d.duration, !dur.isEmpty { return "\(d.category.localizedDisplayName) – \(dur)" }
            return d.category.localizedDisplayName
        }
        return String(localized: "Visa Required")
    }

    private var subtitleColor: Color {
        if let p = appState.data.personalVisas.first(where: { $0.countryCode == country.code }) {
            return Self.expiryReminderColor(for: p.expiryDate)
        }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 12) {
            CountryFlag(country: country)
            VStack(alignment: .leading, spacing: 2) {
                Text(country.localizedName()).font(.subheadline.weight(.semibold))
                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(subtitleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
            Circle().fill(category.color).frame(width: 10, height: 10)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private static func expiryReminderColor(for expiryDate: Date) -> Color {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let expiryDay = calendar.startOfDay(for: expiryDate)
        if today > expiryDay { return .red }
        if let warningStart = calendar.date(byAdding: .day, value: -31, to: expiryDay),
           today >= warningStart {
            return .orange
        }
        return .secondary
    }
}

private struct CountryFlag: View {
    let country: Country

    var body: some View {
        Group {
            if country.flag.isEmpty {
                Image(systemName: "flag.fill")
                    .foregroundStyle(.secondary)
            } else {
                Text(country.flag)
            }
        }
        .font(.title3)
        .frame(width: 24)
        .accessibilityLabel(
            country.flag.isEmpty
                ? String(localized: "Flag unavailable")
                : String(localized: "Flag of \(country.localizedName())")
        )
    }
}

private struct EntryPolicySheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCountry: Country?
    @State private var category: VisaCategory
    @State private var policyDuration: String
    @State private var showCountryPicker = false

    // Personal visa editing state (used only when a personal visa exists for the selected country)
    @State private var personalVisaID: UUID?
    @State private var visaType: String
    @State private var visaDuration: String
    @State private var visaExpiry: Date
    @State private var hasVisaExpiry: Bool
    @State private var visaNotes: String
    @State private var showVisaError: Bool = false

    // Attachment state
    @State private var attachmentFileNames: [String]
    @State private var showAttachmentActionSheet = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var photoPickerItem: PhotosPickerItem? = nil
    @State private var showFilePicker = false
    @State private var previewingAttachment: AttachmentPreviewItem? = nil

    init(country: Country, existingEntry: DefaultVisaEntry?, existingPersonalVisa: PersonalVisa?) {
        _selectedCountry = State(initialValue: country)
        _category = State(initialValue: existingEntry?.category ?? .visaFree)
        _policyDuration = State(initialValue: existingEntry?.duration ?? "")
        _personalVisaID = State(initialValue: existingPersonalVisa?.id)
        _visaType = State(initialValue: existingPersonalVisa?.visaType ?? "")
        _visaDuration = State(initialValue: existingPersonalVisa?.duration ?? "")
        _visaExpiry = State(
            initialValue: existingPersonalVisa?.expiryDate
                ?? Date().addingTimeInterval(60 * 60 * 24 * 365)
        )
        _hasVisaExpiry = State(initialValue: existingPersonalVisa?.expiryDate != nil)
        _visaNotes = State(initialValue: existingPersonalVisa?.notes ?? "")
        _attachmentFileNames = State(initialValue: existingPersonalVisa?.attachmentFileNames ?? [])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    formLabel("COUNTRY")
                    Button {
                        showCountryPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            if let selectedCountry {
                                CountryFlag(country: selectedCountry)
                                Text(selectedCountry.localizedName())
                                    .foregroundStyle(.primary)
                            } else {
                                Text("Select a country")
                                    .foregroundStyle(.secondary)
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

                    formLabel("ENTRY POLICY TYPE")
                    Picker("Entry policy type", selection: $category) {
                        Text("Visa Free").tag(VisaCategory.visaFree)
                        Text("Visa on Arrival").tag(VisaCategory.visaOnArrival)
                        Text("ETA").tag(VisaCategory.eta)
                    }
                    .pickerStyle(.segmented)

                    formLabel("DURATION")
                    HStack {
                        TextField("e.g., 30 days", text: $policyDuration)
                        if !policyDuration.isEmpty {
                            Button { policyDuration = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

                    if hasExistingPolicy {
                        Button("Remove Policy", role: .destructive) {
                            guard let selectedCountry else { return }
                            appState.removeDefaultVisa(selectedCountry.code)
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                    }

                    if hasPersonalVisa {
                        Divider().padding(.vertical, 8)

                        Text("Personal Visa").font(.headline)

                        formLabel("VISA TYPE")
                        HStack {
                            TextField("e.g., Single / Multiple / Student / Work", text: $visaType)
                            if !visaType.isEmpty {
                                Button { visaType = "" } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

                        formLabel("DURATION PER VISIT")
                        HStack {
                            TextField("e.g., 90 days", text: $visaDuration)
                            if !visaDuration.isEmpty {
                                Button { visaDuration = "" } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

                        formLabel("EXPIRY DATE")
                        if hasVisaExpiry {
                            HStack {
                                DatePicker("", selection: $visaExpiry, displayedComponents: .date)
                                    .labelsHidden()
                                    .datePickerStyle(.graphical)
                                Spacer()
                                Button {
                                    withAnimation { hasVisaExpiry = false }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding()
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        } else {
                            Button {
                                withAnimation { hasVisaExpiry = true }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "calendar.badge.plus")
                                    Text("Set expiry date")
                                    Spacer()
                                }
                                .padding()
                                .foregroundStyle(.primary)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }

                        formLabel("NOTES (OPTIONAL)")
                        TextField("Additional notes\u{2026}", text: $visaNotes, axis: .vertical)
                            .lineLimit(3...6)
                            .padding()
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

                        Divider()
                            .padding(.vertical, 4)

                        formLabel("ATTACHMENTS (OPTIONAL)")
                        Button {
                            showAttachmentActionSheet = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "paperclip")
                                Text("Add Attachment")
                                Spacer()
                            }
                            .padding()
                            .foregroundStyle(.primary)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .confirmationDialog("Add Attachment", isPresented: $showAttachmentActionSheet) {
                            Button("Take a Photo") { showCamera = true }
                            Button("Choose from Photo Album") { showPhotoPicker = true }
                            Button("Choose from File") { showFilePicker = true }
                        }

                        if !attachmentFileNames.isEmpty {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 80), spacing: 8)],
                                spacing: 8
                            ) {
                                ForEach(attachmentFileNames, id: \.self) { name in
                                    if let id = personalVisaID {
                                        AttachmentThumbnailView(
                                            fileName: name,
                                            visaID: id,
                                            onTap: { previewingAttachment = AttachmentPreviewItem(id: name) },
                                            onDelete: { attachmentFileNames.removeAll { $0 == name } }
                                        )
                                    }
                                }
                            }
                        }

                        if showVisaError, let message = visaValidationMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(message)
                            }
                            .font(.caption)
                            .foregroundStyle(.red)
                            .transition(.opacity)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Entry Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { commitChanges() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerSheet(selected: $selectedCountry)
        }
        .sheet(item: $previewingAttachment) { item in
            if let id = personalVisaID {
                VisaAttachmentPreviewSheet(fileName: item.id, visaID: id)
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoPickerItem, matching: .images)
        .onChange(of: photoPickerItem) { _, item in
            Task { @MainActor in
                defer { photoPickerItem = nil }
                guard let item,
                      let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let jpeg = image.jpegData(compressionQuality: 0.85),
                      let id = personalVisaID else { return }
                saveAttachment(data: jpeg, ext: "jpg", visaID: id)
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.image, .pdf],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first,
                  let id = personalVisaID else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { return }
            let ext = url.pathExtension.isEmpty ? "dat" : url.pathExtension
            saveAttachment(data: data, ext: ext, visaID: id)
        }
        .fullScreenCover(isPresented: $showCamera) {
            if let id = personalVisaID {
                CameraImagePicker { image in
                    guard let jpeg = image.jpegData(compressionQuality: 0.85) else { return }
                    saveAttachment(data: jpeg, ext: "jpg", visaID: id)
                }
                .ignoresSafeArea()
            }
        }
        .onChange(of: selectedCountry) { _, country in
            loadDataForCountry(country)
        }
        .onChange(of: visaType) { _, _ in refreshVisaErrorVisibility() }
        .onChange(of: visaDuration) { _, _ in refreshVisaErrorVisibility() }
        .onChange(of: hasVisaExpiry) { _, _ in refreshVisaErrorVisibility() }
    }

    private var hasExistingPolicy: Bool {
        guard let selectedCountry else { return false }
        return appState.data.defaultVisas.contains { $0.countryCode == selectedCountry.code }
    }

    private var hasPersonalVisa: Bool { personalVisaID != nil }

    private var isPersonalVisaValid: Bool {
        !visaType.trimmingCharacters(in: .whitespaces).isEmpty &&
        !visaDuration.trimmingCharacters(in: .whitespaces).isEmpty &&
        hasVisaExpiry
    }

    private var visaValidationMessage: String? {
        guard hasPersonalVisa, !isPersonalVisaValid else { return nil }
        return String(localized: "Please fill in Visa Type, Duration and Expiry Date.")
    }

    private var canSave: Bool {
        guard selectedCountry != nil else { return false }
        return hasPersonalVisa ? isPersonalVisaValid : true
    }

    private func commitChanges() {
        guard let selectedCountry else { return }
        if hasPersonalVisa, !isPersonalVisaValid {
            withAnimation { showVisaError = true }
            return
        }

        appState.addDefaultVisa(
            DefaultVisaEntry(
                countryCode: selectedCountry.code,
                category: category,
                duration: policyDuration.isEmpty ? nil : policyDuration
            )
        )

        if let personalVisaID {
            appState.updatePersonalVisa(
                PersonalVisa(
                    id: personalVisaID,
                    countryCode: selectedCountry.code,
                    visaType: visaType,
                    duration: visaDuration,
                    expiryDate: visaExpiry,
                    notes: visaNotes.isEmpty ? nil : visaNotes,
                    attachmentFileNames: attachmentFileNames
                )
            )
        }

        dismiss()
    }

    private func loadDataForCountry(_ country: Country?) {
        guard let country else { return }
        let entry = appState.data.defaultVisas.first { $0.countryCode == country.code }
        category = entry?.category ?? .visaFree
        policyDuration = entry?.duration ?? ""

        let visa = appState.data.personalVisas.first { $0.countryCode == country.code }
        personalVisaID = visa?.id
        visaType = visa?.visaType ?? ""
        visaDuration = visa?.duration ?? ""
        visaExpiry = visa?.expiryDate ?? Date().addingTimeInterval(60 * 60 * 24 * 365)
        hasVisaExpiry = visa?.expiryDate != nil
        visaNotes = visa?.notes ?? ""
        attachmentFileNames = visa?.attachmentFileNames ?? []
        showVisaError = false
    }

    private func refreshVisaErrorVisibility() {
        guard showVisaError, isPersonalVisaValid else { return }
        withAnimation { showVisaError = false }
    }

    private func saveAttachment(data: Data, ext: String, visaID: UUID) {
        if let name = try? VisaAttachmentStore.save(data: data, fileExtension: ext, for: visaID) {
            attachmentFileNames.append(name)
        }
    }

    private func formLabel(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}
