import SwiftUI

struct ManageDataTab: View {
    @EnvironmentObject var appState: AppState
    @State private var country: Country? = nil
    @State private var category: VisaCategory = .visaFree
    @State private var duration: String = ""
    @State private var showCountryPicker = false
    @State private var confirmReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Manage Default Visa Data").font(.headline)
                Text("Add or remove visa-free, visa-on-arrival, and ETA countries for your selected passport.")
                    .font(.caption).foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Button { showCountryPicker = true } label: {
                        HStack {
                            Text(country.map { "\($0.flag)  \($0.name)" } ?? "Select country…")
                                .foregroundStyle(country == nil ? .secondary : .primary)
                                .foregroundStyle(.black)
                            Spacer()
                            Image(systemName: "chevron.down").foregroundStyle(.black)
                        }
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }

                    Picker("Visa type", selection: $category) {
                        Text("Visa Free").tag(VisaCategory.visaFree)
                        Text("Visa on Arrival").tag(VisaCategory.visaOnArrival)
                        Text("ETA").tag(VisaCategory.eta)
                    }
                    .pickerStyle(.segmented)

                    TextField("Duration (e.g., 30 days)", text: $duration)
                        .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

                    Button(action: addEntry) {
                        Text("ADD")
                            .font(.headline).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding()
                            .background(country == nil ? Color.gray.opacity(0.6) : Color.black,
                                        in: RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(country == nil)
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

                ForEach(sortedDefaults) { entry in
                    defaultRow(entry)
                }

                Button {
                    confirmReset = true
                } label: {
                    Text("RESET TO DEFAULT DATA")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity).padding()
                        .foregroundStyle(.black)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
                .confirmationDialog(
                    "Reset to bundled defaults? Your custom edits will be lost.",
                    isPresented: $confirmReset, titleVisibility: .visible
                ) {
                    Button("Reset", role: .destructive) { appState.resetDefaultsToBundled() }
                    Button("Cancel", role: .cancel) {}
                }
            }
            .padding()
        }
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerSheet(selected: $country)
        }
    }

    private var sortedDefaults: [DefaultVisaEntry] {
        appState.data.defaultVisas.sorted { a, b in
            (appState.country(for: a.countryCode)?.name ?? "") <
            (appState.country(for: b.countryCode)?.name ?? "")
        }
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

    @ViewBuilder
    private func defaultRow(_ entry: DefaultVisaEntry) -> some View {
        let c = appState.country(for: entry.countryCode)
        HStack {
            Text(c?.flag ?? "")
            VStack(alignment: .leading, spacing: 2) {
                Text(c?.name ?? entry.countryCode).font(.subheadline.bold())
                Text("\(entry.category.displayName)\(entry.duration.map { " – \($0)" } ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                appState.removeDefaultVisa(entry.countryCode)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.black)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
