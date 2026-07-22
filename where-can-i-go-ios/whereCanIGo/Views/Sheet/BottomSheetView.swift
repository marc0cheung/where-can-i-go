import SwiftUI

enum PanelTab: String, CaseIterable, Hashable {
    case overview   = "Overview"
    case myVisas    = "My Visas"
    case manageData = "Manage Data"
}

/// Persistent sheet header shown above the TabView across all tabs.
struct SheetHeader: View {
    @EnvironmentObject var appState: AppState
    @State private var showPassportPicker = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Where Can I Go?")
                        .font(.title2.bold())
                        .padding(.top, 10)
                        .padding(.leading, 6)
                    Text(passportLabel)
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(6)
                }
                Spacer()
                Button {
                    randomSelectAccessibleCountry()
                } label: {
                    Image(systemName: "dice.fill")
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .padding(10)
                }
                .buttonStyle(.glass)
                .disabled(appState.diceSpinTarget != nil)
                .accessibilityLabel("Random select a country")
                Button {
                    showPassportPicker = true
                } label: {
                    Image(systemName: "person.text.rectangle.fill")
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .padding(10)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Change passport")
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 14)

            Divider()
        }
        .sheet(isPresented: $showPassportPicker) {
            PassportPickerView(isFirstLaunch: false)
        }
    }

    private var passportLabel: String {
        let c = appState.country(for: appState.data.passportCode)
        return "\(c?.flag ?? "🛂") \(c?.name ?? appState.data.passportCode) Passport"
    }

    private func randomSelectAccessibleCountry() {
        let now = Date()
        let eligible = appState.countries.filter { country in
            let code = country.code
            if let personal = appState.data.personalVisas.first(where: { $0.countryCode == code }) {
                return personal.expiryDate > now
            }
            if let entry = appState.data.defaultVisas.first(where: { $0.countryCode == code }) {
                return entry.category == .visaFree || entry.category == .visaOnArrival
            }
            return false
        }
        if let picked = eligible.randomElement() {
            appState.diceSpinTarget = picked.code
        }
    }
}
