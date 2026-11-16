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

            CapsuleSearchField(text: $search)
                .padding(.horizontal)

            List {
                let countries = appState.countries.filtered(matching: search)
                passportSection("Supported Passports",
                                countries: countries.filter { supportedPassportCodes.contains($0.code) })
                passportSection("More to come…",
                                countries: countries.filter { !supportedPassportCodes.contains($0.code) })
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
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(.black)
            .disabled(!supportedPassportCodes.contains(selectedCode))
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
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(.black)
            .padding()
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private func passportSection(_ title: LocalizedStringKey, countries: [Country]) -> some View {
        if !countries.isEmpty {
            Section {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)
                    .listRowSeparator(.hidden)
                    .accessibilityAddTraits(.isHeader)

                ForEach(countries, id: \.code) { country in
                    passportRow(country)
                }
            }
        }
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
}
