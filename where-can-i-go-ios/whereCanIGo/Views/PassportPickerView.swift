import SwiftUI

struct PassportPickerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let isFirstLaunch: Bool
    @State private var search: String = ""
    @State private var selectedCode: String = "HKG"

    var body: some View {
        NavigationStack {
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
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)

                List(filtered, id: \.code) { country in
                    HStack {
                        Text(country.flag)
                        Text(country.name)
                        Spacer()
                        if country.code == selectedCode {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { selectedCode = country.code }
                }
                .listStyle(.plain)

                Button {
                    appState.completePassportSelection(selectedCode)
                    if !isFirstLaunch { dismiss() }
                } label: {
                    Text("Use this Passport")
                        .font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding()
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .navigationTitle(isFirstLaunch ? "" : "Change Passport")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isFirstLaunch {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .onAppear { selectedCode = appState.data.passportCode }
    }

    private var filtered: [Country] {
        if search.isEmpty { return appState.countries }
        return appState.countries.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
}
