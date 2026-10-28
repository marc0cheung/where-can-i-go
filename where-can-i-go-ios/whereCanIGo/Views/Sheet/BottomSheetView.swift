import SwiftUI

enum PanelTab: String, CaseIterable, Hashable {
    case overview   = "Overview"
    case myVisas    = "My Visas"
    case myTravels  = "Travels"
    case manageData = "Manage Data"

    var localizedTitle: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .myVisas: String(localized: "My Visas")
        case .myTravels: String(localized: "Travels")
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
    @Binding var selectedDiceAirlines: Set<String>
    @Binding var diceIncludesAllEntryRequirements: Bool
    @EnvironmentObject private var profileStore: UserProfileStore
    @EnvironmentObject private var friendStore: FriendStore
    @State private var showProfileMenu = false
    @State private var showProfile = false
    @State private var showSettings = false
    @State private var showNoMatchingCountries = false
    @State private var showAirlineDataError = false

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
                profileMenu
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 14)

            Divider()
        }
        .sheet(isPresented: $showProfile) {
            UserProfileView(profileStore: profileStore, passportCode: appState.data.passportCode)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(appState: appState, profileStore: profileStore, friendStore: friendStore)
        }
        .alert("Unable to Load Profile", isPresented: Binding {
            profileStore.loadError != nil
        } set: { isPresented in
            if !isPresented { profileStore.loadError = nil }
        }) {
            Button("Retry") { profileStore.load() }
            Button("Close", role: .cancel) { profileStore.loadError = nil }
        } message: {
            Text(profileStore.loadError ?? "")
        }
        .alert("No Matching Countries", isPresented: $showNoMatchingCountries) {
            if !selectedDiceContinents.isEmpty {
                Button("All Continents") {
                    selectedDiceContinents.removeAll()
                }
                if !selectedDiceAirlines.isEmpty {
                    Button("Remove Airline Restriction") {
                        selectedDiceAirlines.removeAll()
                    }
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text("No countries match your current passport and dice options.")
        }
        .alert("Airline Data Unavailable", isPresented: $showAirlineDataError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Unable to load airline destinations. Please restart the app or report this issue.")
        }
    }

    private var profileMenu: some View {
        Button {
            showProfileMenu = true
        } label: {
            ProfileAvatar(photoData: profileStore.profile.photoData, size: 32)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.glass)
        .accessibilityLabel("User Profile")
        .accessibilityValue(profileStore.profile.displayName)
        .popover(isPresented: $showProfileMenu, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    showProfileMenu = false
                    if profileStore.loadFailed {
                        profileStore.load()
                    }
                    if !profileStore.loadFailed {
                        showProfile = true
                    }
                } label: {
                    HStack(spacing: 14) {
                        ProfileAvatar(photoData: profileStore.profile.photoData, size: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profileStore.profile.displayName)
                                .font(.headline)
                            Text("Edit Profile")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                Divider()
                Button {
                    showProfileMenu = false
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .font(.body)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .padding(20)
            .frame(minWidth: 260, maxWidth: 340)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var diceMenu: some View {
        // The badge is a persistent sibling (not a conditional overlay) so it isn't re-inserted
        // beneath the Liquid Glass button while the menu morph transition is active.
        ZStack(alignment: .topTrailing) {
            diceMenuButton
            diceBadge
                .zIndex(1)
        }
    }

    private var diceFilterCount: Int {
        selectedDiceContinents.count + selectedDiceAirlines.count
    }

    private var diceBadge: some View {
        Text(diceFilterCount, format: .number)
            .font(.system(size: 11, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(.red, in: Circle())
            .offset(x: 4, y: -4)
            .opacity(diceFilterCount > 0 ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var diceMenuButton: some View {
        Menu {
            Menu {
                Toggle("All Continents", isOn: allDiceContinentsBinding)
                Divider()
                ForEach(Continent.allCases, id: \.self) { continent in
                    Toggle(continentTitle(continent), isOn: diceContinentBinding(continent))
                }
            } label: {
                Label("Continent", systemImage: "globe")
            }
            Menu {
                if case .success = AirlineRepository.catalog {
                    Toggle("No Airline Restriction", isOn: noDiceAirlineRestrictionBinding)
                    Toggle("All Airlines", isOn: allDiceAirlinesBinding)
                    Divider()
                    ForEach(diceAirlines) { airline in
                        Toggle(isOn: diceAirlineBinding(airline.id)) {
                            Label {
                                Text(airline.localizedName)
                            } icon: {
                                Image(airline.logoAssetName)
                                    .renderingMode(.original)
                            }
                        }
                    }
                } else {
                    Button("Airline Data Unavailable") {
                        showAirlineDataError = true
                    }
                }
            } label: {
                Label("Airlines", systemImage: "airplane")
            }
            Divider()
            Toggle("Accessible Countries Only", isOn: accessibleDiceCountriesOnlyBinding)
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

    private var diceAirlines: [Airline] {
        if case let .success(airlines) = AirlineRepository.catalog {
            return airlines
        }
        return []
    }

    private var allDiceAirlinesBinding: Binding<Bool> {
        Binding {
            !diceAirlines.isEmpty && Set(diceAirlines.map(\.id)).isSubset(of: selectedDiceAirlines)
        } set: { isSelected in
            selectedDiceAirlines = isSelected ? Set(diceAirlines.map(\.id)) : []
        }
    }

    private var noDiceAirlineRestrictionBinding: Binding<Bool> {
        Binding {
            selectedDiceAirlines.isEmpty
        } set: { isSelected in
            if isSelected {
                selectedDiceAirlines.removeAll()
            }
        }
    }

    private var accessibleDiceCountriesOnlyBinding: Binding<Bool> {
        Binding {
            !diceIncludesAllEntryRequirements
        } set: { isSelected in
            diceIncludesAllEntryRequirements = !isSelected
        }
    }

    private func diceAirlineBinding(_ id: String) -> Binding<Bool> {
        Binding {
            selectedDiceAirlines.contains(id)
        } set: { isSelected in
            if isSelected {
                selectedDiceAirlines.insert(id)
            } else {
                selectedDiceAirlines.remove(id)
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
        let airlines = selectedDiceAirlines.isEmpty
            ? String(localized: "No Airline Restriction")
            : diceAirlines.filter { selectedDiceAirlines.contains($0.id) }
                .map(\.localizedName).joined(separator: ", ")
        return [continents, airlines, entryRequirements].joined(separator: ", ")
    }

    private var passportLabel: String {
        let c = appState.country(for: appState.data.passportCode)
        let countryName = c?.localizedName() ?? appState.data.passportCode
        return String(localized: "\(c?.flag ?? "🛂") \(countryName) Passport")
    }

    private func randomSelectCountry() {
        guard appState.diceSpinTarget == nil else { return }
        guard case let .success(airlines) = AirlineRepository.catalog else {
            showAirlineDataError = true
            return
        }
        let airlineDestinations = AirlineRepository.destinationCodes(for: selectedDiceAirlines, in: airlines)
        let eligible = appState.countries.filter { country in
            guard country.code != appState.data.passportCode else { return false }
            let continent = Continent.of(country.code) ?? (["HKG", "MAC"].contains(country.code) ? .asia : nil)
            let matchesContinent = selectedDiceContinents.isEmpty ||
                continent.map { selectedDiceContinents.contains($0) } == true
            let matchesAirline = selectedDiceAirlines.isEmpty || airlineDestinations.contains(country.code)
            return matchesContinent && matchesAirline &&
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
