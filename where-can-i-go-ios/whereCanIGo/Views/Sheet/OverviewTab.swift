import SwiftUI

struct OverviewTab: View {
    @EnvironmentObject var appState: AppState
    @State private var search: String = ""

    private var counts: (vf: Int, voa: Int, mine: Int, total: Int) {
        let vf = appState.data.defaultVisas.filter { $0.category == .visaFree }.count
        let voa = appState.data.defaultVisas.filter { $0.category == .visaOnArrival }.count
        let mine = appState.data.personalVisas.count
        return (vf, voa, mine, vf + voa + mine)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatCard(value: counts.vf,    label: "Visa Free",        color: VisaCategory.visaFree.color)
                    StatCard(value: counts.voa,   label: "Visa on Arrival",  color: VisaCategory.visaOnArrival.color)
                    StatCard(value: counts.mine,  label: "My Visas",         color: VisaCategory.myVisa.color)
                    StatCard(value: counts.total, label: "Total Accessible", color: .primary)
                }
                .padding(.horizontal)

                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search countries…", text: $search)
                        .autocorrectionDisabled()
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)

                LazyVStack(spacing: 8) {
                    ForEach(filteredCountries) { country in
                        CountryRow(country: country)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .padding(.top, 12)
        }
    }

    private var filteredCountries: [Country] {
        if search.isEmpty { return appState.countries }
        return appState.countries.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
}

private struct StatCard: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.system(size: 32, weight: .bold))
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.4), lineWidth: 1)
        )
    }
}

private struct CountryRow: View {
    @EnvironmentObject var appState: AppState
    let country: Country

    private var category: VisaCategory { appState.visaCategory(for: country.code) }

    private var subtitle: String {
        if let p = appState.data.personalVisas.first(where: { $0.countryCode == country.code }) {
            return "My Visa – \(p.visaType)"
        }
        if let d = appState.data.defaultVisas.first(where: { $0.countryCode == country.code }) {
            if let dur = d.duration, !dur.isEmpty { return "\(d.category.displayName) – \(dur)" }
            return d.category.displayName
        }
        return "Visa Required"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(country.flag).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(country.name).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Circle().fill(category.color).frame(width: 10, height: 10)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
