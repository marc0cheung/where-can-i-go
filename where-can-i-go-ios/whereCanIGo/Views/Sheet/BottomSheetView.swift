import SwiftUI

enum PanelTab: String, CaseIterable, Hashable {
    case overview   = "Overview"
    case myVisas    = "My Visas"
    case myTravels  = "My Travels"
    case manageData = "Manage Data"
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
                    withAnimation(.smooth(duration: 0.25)) { panelState = .low }
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
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let eligible = appState.countries.filter { country in
            let code = country.code
            if let personal = appState.data.personalVisas.first(where: { $0.countryCode == code }) {
                return calendar.startOfDay(for: personal.expiryDate) >= today
            }
            if let entry = appState.data.defaultVisas.first(where: { $0.countryCode == code }) {
                return entry.category == .visaFree || entry.category == .visaOnArrival
            }
            return false
        }
        if let picked = eligible.randomElement() {
            appState.selectedCountryCode = nil
            appState.diceSpinTarget = picked.code
        }
    }
}
