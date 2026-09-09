import SwiftUI

/// A compact floating card shown when the user taps a country on the map.
/// Displays the country flag, name, visa category, duration, and a dismiss button.
struct CountryDetailCard: View {
    @EnvironmentObject var appState: AppState
    let countryCode: String
    @Binding var selectedTab: PanelTab
    @Binding var panelState: PanelState

    private var country: Country? { appState.country(for: countryCode) }

    private var category: VisaCategory { appState.visaCategory(for: countryCode) }

    private var duration: String? {
        if let personal = appState.data.personalVisas.first(where: { $0.countryCode == countryCode }) {
            return personal.duration
        }
        return appState.data.defaultVisas.first(where: { $0.countryCode == countryCode })?.duration
    }

    var body: some View {
        HStack(spacing: 14) {
            // Flag
            Text(country?.flag ?? "🏳️")
                .font(.system(size: 44))

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(country?.name ?? countryCode)
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                Text(category.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))

                if let dur = duration, !dur.isEmpty {
                    Text(dur)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if category == .visaRequired {
                    Button {
                        appState.pendingAddVisaCountryCode = countryCode
                        selectedTab = .myVisas
                        withAnimation(.smooth(duration: 0.25)) { panelState = .medium }
                        appState.selectCountry(code: nil)
                    } label: {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(.white.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add Visa")
                }

                Button {
                    appState.pendingAddVisitCountryCode = countryCode
                    selectedTab = .myTravels
                    withAnimation(.smooth(duration: 0.25)) { panelState = .medium }
                    appState.selectCountry(code: nil)
                } label: {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.18), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark as visited")

                Button {
                    appState.selectCountry(code: nil)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.15), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black.opacity(0.82))
                .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 16)
    }
}
