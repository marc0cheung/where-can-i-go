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
    @Namespace private var tabAnimation

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
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

                bottomTabBar
                    .padding(.horizontal, 14)
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
                    .padding(10)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel("Change passport")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }
    
    @Namespace private var tabSelectionNS

    private var bottomTabBar: some View {
        HStack(spacing: 0) {
            ForEach(PanelTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(6)
        .glassEffect(.regular.interactive(), in: Capsule())
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func tabButton(_ tab: PanelTab) -> some View {
        let isSelected = selectedTab == tab

        Button {
            withAnimation(.smooth(duration: 0.35, extraBounce: 0.15)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: iconName(for: tab))
                    .font(.system(size: 18, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(tab.rawValue)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.accentColor)
                        .matchedGeometryEffect(id: "selectedPill", in: tabSelectionNS)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func iconName(for tab: PanelTab) -> String {
        switch tab {
        case .overview:   return "globe.asia.australia.fill"
        case .myVisas:    return "person.text.rectangle.fill"
        case .manageData: return "slider.horizontal.3"
        }
    }

    private var passportLabel: String {
        let c = appState.country(for: appState.data.passportCode)
        return "\(c?.flag ?? "🛂") \(c?.name ?? appState.data.passportCode) Passport"
    }
}
