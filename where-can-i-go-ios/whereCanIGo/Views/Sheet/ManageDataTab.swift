import SwiftUI

struct ManageDataTab: View {
    @EnvironmentObject var appState: AppState
    @State private var country: Country? = nil
    @State private var category: VisaCategory = .visaFree
    @State private var duration: String = ""
    @State private var showCountryPicker = false
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                Button { showCountryPicker = true } label: {
                    HStack {
                        Text(country.map { "\($0.flag)  \($0.localizedName())" } ?? String(localized: "Select country…"))
                            .foregroundStyle(country == nil ? .secondary : .primary)
                        Spacer()
                        Image(systemName: "chevron.down").foregroundStyle(.gray)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Picker("Visa type", selection: $category) {
                    Text("Visa Free").tag(VisaCategory.visaFree)
                    Text("Visa on Arrival").tag(VisaCategory.visaOnArrival)
                    Text("ETA").tag(VisaCategory.eta)
                }
                .pickerStyle(.segmented)

                TextField("Duration (e.g., 30 days)", text: $duration)

                Button(action: addEntry) {
                    Text("ADD")
                        .font(.headline)
                        .foregroundStyle(Color(.systemBackground))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(.primary)
                .disabled(country == nil)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manage Default Entry Policy").font(.headline).foregroundStyle(.primary)
                    Text("Add or remove visa-free, visa-on-arrival, and ETA countries for your selected passport.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .textCase(nil)
            }

            if !sortedDefaults.isEmpty {
                Section {
                    ForEach(sortedDefaults) { entry in
                        defaultRow(entry)
                    }
                }
            }

            Section {
                Button {
                    confirmReset = true
                } label: {
                    Text("RESET TO DEFAULT DATA")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.primary)
                }
                .confirmationDialog(
                    "Reset to bundled defaults? Your custom edits will be lost.",
                    isPresented: $confirmReset, titleVisibility: .visible
                ) {
                    Button("Reset", role: .destructive) { appState.resetDefaultsToBundled() }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerSheet(selected: $country)
        }
        .onDisappear {
            resetDraft()
        }
    }

    private var sortedDefaults: [DefaultVisaEntry] {
        appState.data.defaultVisas
            .map { (entry: $0, name: appState.country(for: $0.countryCode)?.localizedName() ?? "") }
            .sorted { $0.name < $1.name }
            .map(\.entry)
    }

    private func addEntry() {
        guard let c = country else { return }
        let entry = DefaultVisaEntry(
            countryCode: c.code,
            category: category,
            duration: duration.isEmpty ? nil : duration
        )
        appState.addDefaultVisa(entry)
        country = nil; duration = ""
    }

    private func resetDraft() {
        country = nil
        category = .visaFree
        duration = ""
        showCountryPicker = false
    }

    @ViewBuilder
    private func defaultRow(_ entry: DefaultVisaEntry) -> some View {
        let c = appState.country(for: entry.countryCode)
        HStack {
            Text(c?.flag ?? "")
            VStack(alignment: .leading, spacing: 2) {
                Text(c?.localizedName() ?? entry.countryCode).font(.subheadline.bold())
                Text("\(entry.category.localizedDisplayName)\(entry.duration.map { " – \($0)" } ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                appState.removeDefaultVisa(entry.countryCode)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.gray)
            }
            .buttonStyle(.plain)
        }
    }
}
