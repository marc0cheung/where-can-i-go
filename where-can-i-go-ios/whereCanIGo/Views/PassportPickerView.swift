import SwiftUI

struct PassportPickerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let isFirstLaunch: Bool
    @State private var search: String = ""
    @State private var selectedCode: String = "HKG"

    private let supportedPassportCodes: Set<String> = ["CHN", "HKG"]

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
                    appState.completePassportSelection(selectedCode)
                    if !isFirstLaunch { dismiss() }
                } label: {
                    Text("Use this Passport")
                        .font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
                }
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
        .onAppear { selectedCode = appState.data.passportCode }
    }

    private func passportRow(_ country: Country) -> some View {
        HStack {
            Text(country.flag)
            Text(country.localizedName())
            Spacer()
            if country.code == selectedCode {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.primary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedCode = country.code }
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
