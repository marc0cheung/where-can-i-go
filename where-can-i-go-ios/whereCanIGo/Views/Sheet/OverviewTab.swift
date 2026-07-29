import SwiftUI

struct OverviewTab: View {
    @EnvironmentObject var appState: AppState
    @State private var search: String = ""
    @State private var isCompactHeight = false
    @State private var countryBeingEdited: Country? = nil
    @State private var confirmReset = false

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
                                StatCard(value: counts.vf,    label: "Visa Free",        color: VisaCategory.visaFree.color)
                                StatCard(value: counts.voa,   label: "Visa on Arrival",  color: VisaCategory.visaOnArrival.color)
                                StatCard(value: counts.eta,   label: "ETA",              color: VisaCategory.eta.color)
                                StatCard(value: counts.mine,  label: "My Visas",         color: VisaCategory.myVisa.color)
                                StatCard(value: counts.total, label: "Total Accessible", color: .primary)
                            }
                            .padding(.horizontal)
                            .padding(.vertical)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                    } else {
                        VStack(spacing: 10) {
                            HStack(spacing: 10) {
                                StatCard(value: counts.vf, label: "Visa Free", color: VisaCategory.visaFree.color, width: .flexible)
                                StatCard(value: counts.voa, label: "Visa on Arrival", color: VisaCategory.visaOnArrival.color, width: .flexible)
                                StatCard(value: counts.eta, label: "ETA", color: VisaCategory.eta.color, width: .flexible)
                            }
                            HStack(spacing: 10) {
                                StatCard(value: counts.mine, label: "My Visas", color: VisaCategory.myVisa.color, width: .flexible)
                                StatCard(value: counts.total, label: "Total Accessible", color: .primary, width: .flexible)
                            }
                        }
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                    }

                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search countries…", text: $search)
                            .autocorrectionDisabled()
                    }
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)

                    LazyVStack(spacing: 8) {
                        ForEach(filteredCountries) { country in
                            Button {
                                countryBeingEdited = country
                            } label: {
                                CountryRow(country: country)
                            }
                            .buttonStyle(.plain)
                        }

                        if search.isEmpty {
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
                    existingEntry: appState.data.defaultVisas.first { $0.countryCode == country.code }
                )
            }
        }
    }

    private var filteredCountries: [Country] {
        if search.isEmpty { return appState.countries }
        return appState.countries.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
}

private struct StatCard: View {
    enum WidthMode {
        case fixed(CGFloat)
        case flexible
    }

    let value: Int
    let label: String
    let color: Color
    var width: WidthMode = .fixed(152)

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.system(size: 32, weight: .bold))
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: isFlexible ? .infinity : nil)
        .frame(width: fixedWidth)
        .padding(.vertical, 16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color, lineWidth: 1)
        )
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

    private var subtitle: String {
        if let p = appState.data.personalVisas.first(where: { $0.countryCode == country.code }) {
            return "My Visa – \(p.visaType)"
        }
        if let d = appState.data.defaultVisas.first(where: { $0.countryCode == country.code }) {
            if let dur = d.duration, !dur.isEmpty { return "\(d.category.displayName) – \(dur)" }
            return d.category.displayName
        }
        return "Visa Required"
    }

    var body: some View {
        HStack(spacing: 12) {
            CountryFlag(country: country)
            VStack(alignment: .leading, spacing: 2) {
                Text(country.name).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Circle().fill(category.color).frame(width: 10, height: 10)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
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
        .accessibilityLabel(country.flag.isEmpty ? "Flag unavailable" : "Flag of \(country.name)")
    }
}

private struct EntryPolicySheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCountry: Country?
    @State private var category: VisaCategory
    @State private var duration: String
    @State private var showCountryPicker = false

    init(country: Country, existingEntry: DefaultVisaEntry?) {
        _selectedCountry = State(initialValue: country)
        _category = State(initialValue: existingEntry?.category ?? .visaFree)
        _duration = State(initialValue: existingEntry?.duration ?? "")
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
                                Text(selectedCountry.name)
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
                    TextField("e.g., 30 days", text: $duration)
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
                    Button("Done") { savePolicy() }
                        .fontWeight(.semibold)
                        .disabled(selectedCountry == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerSheet(selected: $selectedCountry)
        }
        .onChange(of: selectedCountry) { _, country in
            loadPolicy(for: country)
        }
    }

    private var hasExistingPolicy: Bool {
        guard let selectedCountry else { return false }
        return appState.data.defaultVisas.contains { $0.countryCode == selectedCountry.code }
    }

    private func savePolicy() {
        guard let selectedCountry else { return }
        appState.addDefaultVisa(
            DefaultVisaEntry(
                countryCode: selectedCountry.code,
                category: category,
                duration: duration.isEmpty ? nil : duration
            )
        )
        dismiss()
    }

    private func loadPolicy(for country: Country?) {
        guard let country else { return }
        let entry = appState.data.defaultVisas.first { $0.countryCode == country.code }
        category = entry?.category ?? .visaFree
        duration = entry?.duration ?? ""
    }

    private func formLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}
