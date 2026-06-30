import SwiftUI

struct MyVisasTab: View {
    @EnvironmentObject var appState: AppState
    @State private var country: Country? = nil
    @State private var visaType: String = ""
    @State private var duration: String = ""
    @State private var expiry: Date = Date().addingTimeInterval(60 * 60 * 24 * 365)
    @State private var notes: String = ""
    @State private var showCountryPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add Personal Visa").font(.headline)

                formLabel("COUNTRY")
                Button { showCountryPicker = true } label: {
                    HStack {
                        Text(country.map { "\($0.flag)  \($0.name)" } ?? "Select a country…")
                            .foregroundStyle(country == nil ? .secondary : .primary)
                        Spacer()
                        Image(systemName: "chevron.down").foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }

                formLabel("VISA TYPE")
                TextField("e.g., 3-year multiple entry", text: $visaType)
                    .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

                formLabel("DURATION")
                TextField("e.g., 90 days per visit", text: $duration)
                    .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

                formLabel("EXPIRY DATE")
                DatePicker("", selection: $expiry, displayedComponents: .date)
                    .labelsHidden()
                    .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

                formLabel("NOTES (OPTIONAL)")
                TextField("Additional notes…", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
                    .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))

                Button(action: addVisa) {
                    Text("ADD VISA")
                        .font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding()
                        .background(canAdd ? Color.black : Color.gray.opacity(0.6),
                                    in: RoundedRectangle(cornerRadius: 10))
                }
                .disabled(!canAdd)

                Divider().padding(.vertical, 8)

                // TODO: Excel import — implement in a later release (likely via CoreXLSX SPM package).
                Text("Import from Excel").font(.headline)
                Text("Load visa records from the MyVisa sheet of an .xlsx file.\nColumns: Country, Visa Type, Duration, Expire Date (dd-mm-yyyy), Notes.")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    // TODO: implement Excel import
                } label: {
                    Text("IMPORT EXCEL FILE (Coming Soon)")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity).padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
                .disabled(true)

                Divider().padding(.vertical, 8)

                Text("Saved Personal Visas").font(.headline)
                if appState.data.personalVisas.isEmpty {
                    Text("No personal visas yet.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(appState.data.personalVisas) { visa in
                        personalVisaRow(visa)
                    }
                }
            }
            .padding()
        }
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerSheet(selected: $country)
        }
    }

    private func formLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var canAdd: Bool {
        country != nil && !visaType.isEmpty && !duration.isEmpty
    }

    private func addVisa() {
        guard let c = country else { return }
        let visa = PersonalVisa(
            countryCode: c.code,
            visaType: visaType,
            duration: duration,
            expiryDate: expiry,
            notes: notes.isEmpty ? nil : notes
        )
        appState.addPersonalVisa(visa)
        country = nil; visaType = ""; duration = ""; notes = ""
    }

    @ViewBuilder
    private func personalVisaRow(_ v: PersonalVisa) -> some View {
        let c = appState.country(for: v.countryCode)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(c?.flag ?? "")  \(c?.name ?? v.countryCode)")
                    .font(.subheadline.bold())
                Text("\(v.visaType) · \(v.duration)").font(.caption)
                Text("Expires \(v.expiryDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2).foregroundStyle(.secondary)
                if let notes = v.notes, !notes.isEmpty {
                    Text(notes).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(role: .destructive) {
                appState.removePersonalVisa(v.id)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
