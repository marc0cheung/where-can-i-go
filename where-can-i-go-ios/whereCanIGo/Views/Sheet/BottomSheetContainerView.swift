import SwiftUI

struct BottomSheetContainerView: View {
    @Binding var selectedTab: PanelTab

    var body: some View {
        ZStack(alignment: .bottom) {
            BottomSheetView(selectedTab: $selectedTab)

            FloatingPanelTabBar(selectedTab: $selectedTab)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }
    }
}

struct FloatingPanelTabBar: View {
    @Binding var selectedTab: PanelTab
    @Namespace private var tabSelectionNS

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PanelTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(6)
        .glassEffect(.regular.interactive(), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabs")
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
                Image(systemName: tab.iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(tab.rawValue)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? Color.black : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.gray.opacity(0.10))
                        .matchedGeometryEffect(id: "selectedPill", in: tabSelectionNS)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private extension PanelTab {
    var iconName: String {
        switch self {
        case .overview:   return "globe.asia.australia.fill"
        case .myVisas:    return "person.text.rectangle.fill"
        case .manageData: return "slider.horizontal.3"
        }
    }
}
