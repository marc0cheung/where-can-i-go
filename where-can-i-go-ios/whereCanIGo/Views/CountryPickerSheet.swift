import SwiftUI

struct CountryPickerSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: Country?
    @State private var search: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search countries…", text: $search)
                        .autocorrectionDisabled()
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.top, 8)

                List(filtered) { country in
                    Button {
                        selected = country
                        dismiss()
                    } label: {
                        HStack {
                            Text(country.flag)
                            Text(country.name).foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Select Country")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var filtered: [Country] {
        if search.isEmpty { return appState.countries }
        return appState.countries.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
}
