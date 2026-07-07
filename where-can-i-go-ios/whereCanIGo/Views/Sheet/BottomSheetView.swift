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
                    Text(passportLabel)
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(6)
                }
                Spacer()
                Button {
                    showPassportPicker = true
                } label: {
                    Image(systemName: "person.text.rectangle.fill")
                        .font(.title3)
                        .foregroundStyle(.black)
                        .padding(10)
                        .background(.thinMaterial, in: Circle())
                }
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
}

/*
 
 import SwiftUI

enum PanelTab: String, CaseIterable, Hashable {
    case overview   = "Overview"
    case myVisas    = "My Visas"
    case manageData = "Manage Data"
}

struct BottomSheetView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedTab: PanelTab
    @State private var showPassportPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                Divider()

                Group {
                    switch selectedTab {
                    case .overview:   OverviewTab()
                    case .myVisas:    MyVisasTab()
                    case .manageData: ManageDataTab()
                    }
                }
                .padding(.bottom, 96)
            }
            .sheet(isPresented: $showPassportPicker) {
                PassportPickerView(isFirstLaunch: false)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Where Can I Go?")
                    .font(.title2.bold())
                Text(passportLabel)
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(6)
            }
            Spacer()
            Button {
                showPassportPicker = true
            } label: {
                Image(systemName: "person.text.rectangle.fill")
                    .font(.title3)
                    .foregroundStyle(.black)
                    .padding(10)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel("Change passport")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private var passportLabel: String {
        let c = appState.country(for: appState.data.passportCode)
        return "\(c?.flag ?? "🛂") \(c?.name ?? appState.data.passportCode) Passport"
    }
}

*/
