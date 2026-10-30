import SwiftUI

struct PassportPickerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let isFirstLaunch: Bool
    var initialCode: String? = nil
    var onSelect: ((String) -> Void)? = nil
    @State private var search: String = ""
    @State private var selectedCode: String = "HKG"

    private let supportedPassportCodes: Set<String> = ["CHN", "HKG", "MAC", "TWN"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isFirstLaunch {
                    VStack(spacing: 6) {
                        Text("Welcome 👋").font(.largeTitle.bold())
                        Text("Select your passport country to begin.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 16)
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

                List {
                    if !supportedPassports.isEmpty {
                        Section {
                            Text("Supported Passports")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 16)
                                .listRowSeparator(.hidden)
                                .accessibilityAddTraits(.isHeader)

                            ForEach(supportedPassports, id: \.code) { country in
                                passportRow(country)
                            }
                        }
                    }

                    if !unsupportedPassports.isEmpty {
                        Section {
                            Text("More to come…")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 16)
                                .listRowSeparator(.hidden)
                                .accessibilityAddTraits(.isHeader)

                            ForEach(unsupportedPassports, id: \.code) { country in
                                passportRow(country)
                            }
                        }
                    }
                }
                .listStyle(.plain)

                Button {
                    if let onSelect {
                        onSelect(selectedCode)
                    } else {
                        appState.completePassportSelection(selectedCode)
                    }
                    if !isFirstLaunch { dismiss() }
                } label: {
                    Text("Use this Passport")
                        .font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!supportedPassportCodes.contains(selectedCode))
                .opacity(supportedPassportCodes.contains(selectedCode) ? 1 : 0.45)
                .padding()
            }
            .navigationTitle(isFirstLaunch ? "" : "Change Passport")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isFirstLaunch {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .onAppear { selectedCode = initialCode ?? appState.data.passportCode }
    }

    private func passportRow(_ country: Country) -> some View {
        let isSupported = supportedPassportCodes.contains(country.code)
        return Button {
            selectedCode = country.code
        } label: {
            HStack {
                Text(country.flag)
                Text(country.localizedName())
                Spacer()
                if country.code == selectedCode {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.primary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isSupported)
        .opacity(isSupported ? 1 : 0.45)
        .accessibilityHint(isSupported ? Text("") : Text("Entry-policy data is not available for this passport."))
    }

    private var supportedPassports: [Country] {
        filtered.filter { supportedPassportCodes.contains($0.code) }
    }

    private var unsupportedPassports: [Country] {
        filtered.filter { !supportedPassportCodes.contains($0.code) }
    }

    private var filtered: [Country] {
        if search.isEmpty { return appState.countries }
        return appState.countries.filter {
            $0.localizedName().localizedCaseInsensitiveContains(search) ||
            $0.name.localizedCaseInsensitiveContains(search)
        }
    }
}
