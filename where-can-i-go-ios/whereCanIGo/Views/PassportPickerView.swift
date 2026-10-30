import SwiftUI

struct PassportPickerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let isFirstLaunch: Bool
    var initialCode: String? = nil
    var onSelect: ((String) -> Void)? = nil
    @State private var search: String = ""
    @State private var selectedCode: String = "HKG"
    @State private var showsTravelWarning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let supportedPassportCodes: Set<String> = ["CHN", "HKG", "MAC", "TWN"]

    var body: some View {
        NavigationStack {
            ZStack {
                if showsTravelWarning {
                    travelWarningPage
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                } else {
                    pickerPage
                        .transition(reduceMotion ? .opacity : .move(edge: .leading))
                }
            }
            .clipped()
            .navigationTitle(isFirstLaunch ? "" : "Change Passport")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isFirstLaunch {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                } else if showsTravelWarning {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            withAnimation(.smooth) { showsTravelWarning = false }
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel("Back")
                    }
                }
            }
        }
        .onAppear { selectedCode = initialCode ?? appState.data.passportCode }
    }

    private var pickerPage: some View {
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
                } else if isFirstLaunch {
                    withAnimation(.smooth) { showsTravelWarning = true }
                    return
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
        .background(Color(.systemBackground))
    }

    /// First-launch only: shown after a passport is chosen, before the app opens.
    private var travelWarningPage: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.orange)
                        .padding(.top, 48)
                        .accessibilityHidden(true)
                    Text("Before You Travel")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text("travel.warning.body")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity)
            }

            Button {
                appState.completePassportSelection(selectedCode)
            } label: {
                Text("I Understand")
                    .font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding()
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
        .background(Color(.systemBackground))
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
