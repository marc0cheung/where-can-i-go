import SwiftUI

enum PanelTab: String, CaseIterable, Hashable {
    case overview   = "Overview"
    case myVisas    = "My Visas"
    case myTravels  = "My Travels"
    case manageData = "Manage Data"

    var localizedTitle: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .myVisas: String(localized: "My Visas")
        case .myTravels: String(localized: "My Travels")
        case .manageData: String(localized: "Manage Data")
        }
    }
}

/// Height state shared by the compact-width system sheet (iPhone / narrow iPad
/// window) and the regular-width floating panel (wide iPad window). This gives
/// both surfaces the same three-detent behavior.
enum PanelState: Hashable, CaseIterable {
    case low
    case medium
    case high

    /// Detent used when the compact-width `.sheet` is presented.
    var presentationDetent: PresentationDetent {
        switch self {
        case .low:    return .height(290)
        case .medium: return .medium
        case .high:   return .large
        }
    }

    static func from(detent: PresentationDetent) -> PanelState {
        if detent == .medium { return .medium }
        if detent == .large  { return .high }
        return .low
    }

    /// Target height (points) for the regular-width floating panel.
    func iPadHeight(availableHeight: CGFloat) -> CGFloat {
        switch self {
        case .low:
            return 310
        case .medium:
            return max(400, availableHeight * 0.55)
        case .high:
            return max(500, availableHeight - 40)
        }
    }
}

/// Persistent sheet header shown above the TabView across all tabs.
struct SheetHeader: View {
    @EnvironmentObject var appState: AppState
    @Binding var panelState: PanelState
    @Binding var selectedDiceContinents: Set<Continent>
    @Binding var diceIncludesAllEntryRequirements: Bool
    @State private var showPassportPicker = false
    @State private var showNoMatchingCountries = false

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
                diceMenu
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
        .alert("No Matching Countries", isPresented: $showNoMatchingCountries) {
            if !selectedDiceContinents.isEmpty {
                Button("All Continents") {
                    selectedDiceContinents.removeAll()
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text("No countries match your current passport and dice options.")
        }
    }

    private var diceMenu: some View {
        Menu {
            Toggle("All Continents", isOn: allDiceContinentsBinding)
            Divider()
            ForEach(Continent.allCases, id: \.self) { continent in
                Toggle(continentTitle(continent), isOn: diceContinentBinding(continent))
            }
            Divider()
            Toggle("Include All Entry Requirements", isOn: $diceIncludesAllEntryRequirements)
        } label: {
            Image(systemName: "dice.fill")
                .font(.title3)
                .foregroundStyle(diceIncludesAllEntryRequirements ? Color.accentColor : Color.primary)
                .frame(minWidth: 44, minHeight: 44)
        } primaryAction: {
            randomSelectCountry()
        }
        .buttonStyle(.glass)
        .menuActionDismissBehavior(.disabled)
        .disabled(appState.diceSpinTarget != nil)
        .overlay(alignment: .topTrailing) {
            if !selectedDiceContinents.isEmpty {
                Text(selectedDiceContinents.count, format: .number)
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(.red, in: Circle())
                    .offset(x: 4, y: -4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel("Random select a country")
        .accessibilityValue(diceAccessibilityValue)
        .accessibilityHint("Touch and hold to change dice options.")
        .help("Dice Options")
    }

    private var allDiceContinentsBinding: Binding<Bool> {
        Binding {
            selectedDiceContinents.isEmpty
        } set: { _ in
            selectedDiceContinents.removeAll()
        }
    }

    private func diceContinentBinding(_ continent: Continent) -> Binding<Bool> {
        Binding {
            selectedDiceContinents.contains(continent)
        } set: { isSelected in
            if isSelected {
                selectedDiceContinents.insert(continent)
            } else {
                selectedDiceContinents.remove(continent)
            }
        }
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

    private var diceAccessibilityValue: String {
        let continents = selectedDiceContinents.isEmpty
            ? String(localized: "All Continents")
            : Continent.allCases.filter { selectedDiceContinents.contains($0) }
                .map(continentTitle).joined(separator: ", ")
        let entryRequirements = diceIncludesAllEntryRequirements
            ? String(localized: "All Entry Requirements")
            : String(localized: "Accessible Countries Only")
        return String(localized: "\(continents), \(entryRequirements)")
    }

    private var passportLabel: String {
        let c = appState.country(for: appState.data.passportCode)
        let countryName = c?.localizedName() ?? appState.data.passportCode
        return String(localized: "\(c?.flag ?? "🛂") \(countryName) Passport")
    }

    private func randomSelectCountry() {
        guard appState.diceSpinTarget == nil else { return }
        let eligible = appState.countries.filter { country in
            guard country.code != appState.data.passportCode else { return false }
            let continent = Continent.of(country.code) ?? (["HKG", "MAC"].contains(country.code) ? .asia : nil)
            let matchesContinent = selectedDiceContinents.isEmpty ||
                continent.map { selectedDiceContinents.contains($0) } == true
            return matchesContinent &&
                (diceIncludesAllEntryRequirements || appState.visaEligibility(for: country.code).isAccessible)
        }
        guard let picked = eligible.randomElement() else {
            showNoMatchingCountries = true
            return
        }
        appState.selectedCountryCode = nil
        appState.diceSpinTarget = picked.code
        withAnimation(.smooth(duration: 0.25)) { panelState = .low }
    }
}
