import SwiftUI

/// A compact floating card shown when the user taps a country on the map.
/// Displays the country flag, name, visa category, duration, and a dismiss button.
struct CountryDetailCard: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openURL) private var openURL
    @AppStorage(SearchEngine.storageKey) private var searchEngine: SearchEngine = .google
    let countryCode: String
    @Binding var selectedTab: PanelTab
    @Binding var panelState: PanelState
    let onReviewWishlist: () -> Void
    let onShowPolicy: () -> Void

    private var hasPlans: Bool {
        appState.data.plannedTrips.contains { $0.countryCode == countryCode }
    }

    private func duration(for eligibility: VisaEligibility) -> String? {
        if let personal = eligibility.sourceVisa {
            return personal.duration
        }
        return appState.data.defaultVisas.first(where: { $0.countryCode == countryCode })?.duration
    }

    private func startAdding(_ pendingCode: ReferenceWritableKeyPath<AppState, String?>, in tab: PanelTab) {
        appState[keyPath: pendingCode] = countryCode
        selectedTab = tab
        withAnimation(.smooth(duration: 0.25)) { panelState = .medium }
        appState.selectCountry(code: nil)
    }

    private func summary(_ eligibility: VisaEligibility, country: Country?) -> some View {
        HStack(spacing: 14) {
            Text(country?.flag ?? "🏳️")
                .font(.system(size: 44))

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(country?.localizedName() ?? countryCode)
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                if let visa = eligibility.sourceVisa, visa.coverage == .schengenArea {
                    let issuer = appState.country(for: visa.countryCode)?.localizedName() ?? visa.countryCode
                    Text("Schengen visa · Issued by \(issuer)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                } else {
                    Text(eligibility.category.localizedDisplayName)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }

                if let dur = duration(for: eligibility), !dur.isEmpty {
                    Text(dur)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
                if let visa = eligibility.sourceVisa {
                    Text("Expires \(visa.expiryDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    var body: some View {
        let country = appState.country(for: countryCode)
        let eligibility = appState.visaEligibility(for: countryCode)
        HStack(spacing: 14) {
            Button(action: onShowPolicy) { summary(eligibility, country: country) }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Opens entry policy details"))

            HStack(spacing: 0) {
                Menu {
                    if hasPlans {
                        Button(action: onReviewWishlist) {
                            Label("Review Wishlist", systemImage: "heart.fill")
                        }
                    } else {
                        Button {
                            startAdding(\.pendingAddWishlistCountryCode, in: .myTravels)
                        } label: {
                            Label("Add to Wishlist", systemImage: "heart")
                        }
                    }

                    Button {
                        startAdding(\.pendingAddVisitCountryCode, in: .myTravels)
                    } label: {
                        Label("Log a Visit", systemImage: "mappin.and.ellipse")
                    }

                    if eligibility.category == .visaRequired {
                        Button {
                            startAdding(\.pendingAddVisaCountryCode, in: .myVisas)
                        } label: {
                            Label("Add Visa", systemImage: "doc.badge.plus")
                        }
                    }

                    Button {
                        let query = country?.localizedName() ?? countryCode
                        if let url = searchEngine.searchURL(for: query) {
                            openURL(url)
                        }
                    } label: {
                        Label("Search on \(searchEngine.displayName)", systemImage: "magnifyingglass")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.18), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Country actions"))
                .help(Text("Country actions"))

                Button {
                    appState.selectCountry(code: nil)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background(.white.opacity(0.15), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
                .help(Text("Close"))
            }
            .fixedSize()
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
