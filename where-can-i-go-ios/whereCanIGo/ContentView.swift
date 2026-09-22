import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var sheetPresented: Bool = true
    @State private var selectedTab: PanelTab = .overview
    @State private var panelState: PanelState = .low
    /// Live drag delta while the user is dragging the iPad panel handle.
    /// Positive = drag down (panel shrinks). Reset to 0 on release.
    @State private var dragOffset: CGFloat = 0

    // Set to true to compare the original Manage Data tab with the integrated flow.
    private let showsManageDataTab = false

    // Regular size class (iPad / wide window) floating-panel metrics.
    private let regularPanelWidth: CGFloat = 390
    private let regularPanelSideInset: CGFloat = 16
    private let regularPanelBottomInset: CGFloat = 24
    private let regularPanelCornerRadius: CGFloat = 30
    private let regularPanelMinHeight: CGFloat = 220

    private var isRegularWidth: Bool { horizontalSizeClass == .regular }

    private var sheetSolidBackground: Color {
        Color(.systemBackground)
    }

    /// Shared content used both inside the compact-width system sheet and the
    /// regular-width floating panel, so behavior stays identical across modes.
    @ViewBuilder
    private var panelContent: some View {
        VStack(spacing: 0) {
            SheetHeader(panelState: $panelState)

            TabView(selection: $selectedTab) {
                Tab(PanelTab.overview.localizedTitle,
                    systemImage: "globe.asia.australia.fill",
                    value: PanelTab.overview) {
                    OverviewTab()
                }

                Tab(PanelTab.myVisas.localizedTitle,
                    systemImage: "person.text.rectangle.fill",
                    value: PanelTab.myVisas) {
                    MyVisasTab()
                }

                Tab(PanelTab.myTravels.localizedTitle,
                    systemImage: "airplane",
                    value: PanelTab.myTravels) {
                    MyTravelsTab()
                }

                if showsManageDataTab {
                    Tab(PanelTab.manageData.localizedTitle,
                        systemImage: "slider.horizontal.3",
                        value: PanelTab.manageData) {
                        ManageDataTab()
                    }
                }
            }
            .toolbarBackground(sheetSolidBackground, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
        }
        .background(sheetSolidBackground)
    }

    /// The system sheet is only presented in compact width. When the window
    /// widens to a regular size class (e.g. iPad full/large multitasking) the
    /// binding flips to `false` and the sheet is dismissed automatically.
    private var systemSheetPresented: Binding<Bool> {
        Binding(
            get: { !isRegularWidth && sheetPresented },
            set: { sheetPresented = $0 }
        )
    }

    /// Bridge `PanelState` to the system sheet's `PresentationDetent` binding
    /// so the compact-width sheet keeps its native drag-to-resize behavior.
    private var detentBinding: Binding<PresentationDetent> {
        Binding(
            get: { panelState.presentationDetent },
            set: { panelState = PanelState.from(detent: $0) }
        )
    }

    var body: some View {
        GeometryReader { proxy in
            CountryMapView()
                .ignoresSafeArea()
                .overlay(alignment: .bottomLeading) {
                    if isRegularWidth {
                        regularWidthOverlay(availableHeight: proxy.size.height)
                    }
                }
                .overlay(alignment: .bottom) {
                    if !isRegularWidth,
                       let code = appState.selectedCountryCode,
                       appState.country(for: code) != nil {
                        CountryDetailCard(countryCode: code, selectedTab: $selectedTab, panelState: $panelState)
                            .padding(.bottom, 310)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.smooth(duration: 0.25), value: appState.selectedCountryCode)
                .onChange(of: appState.selectedCountryCode) { _, newCode in
                    if newCode != nil {
                        // Collapsing to `.low` on either platform gives the
                        // CountryDetailCard room to appear above the panel.
                        withAnimation(.smooth(duration: 0.25)) { panelState = .low }
                    }
                }
                .sheet(isPresented: systemSheetPresented) {
                    panelContent
                        .presentationDetents([.height(290), .medium, .large], selection: detentBinding)
                        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                        .presentationCornerRadius(55)
                        .presentationDragIndicator(.visible)
                        .interactiveDismissDisabled()
                        .presentationBackground(sheetSolidBackground)
                }
        }
    }

    /// Bottom-leading floating column used on iPad / regular-width windows.
    /// The country detail card (when present) stacks directly above the panel
    /// so both share the same 390pt visual width.
    @ViewBuilder
    private func regularWidthOverlay(availableHeight: CGFloat) -> some View {
        let targetHeight = panelState.iPadHeight(availableHeight: availableHeight)
        let maxHeight = max(regularPanelMinHeight, availableHeight - regularPanelBottomInset - 8)
        let currentHeight = min(maxHeight, max(regularPanelMinHeight, targetHeight - dragOffset))

        VStack(spacing: 12) {
            if let code = appState.selectedCountryCode,
               appState.country(for: code) != nil {
                CountryDetailCard(countryCode: code, selectedTab: $selectedTab, panelState: $panelState)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            iPadFloatingPanel(currentHeight: currentHeight, availableHeight: availableHeight)
                .padding(.horizontal, regularPanelSideInset)
        }
        // Total column width matches the card's built-in 16pt horizontal
        // padding, so the card and the panel align at the same 390pt width.
        .frame(width: regularPanelWidth + regularPanelSideInset * 2)
        .padding(.bottom, regularPanelBottomInset)
    }

    /// The rounded panel itself: drag handle at top, then the shared
    /// `panelContent`. Forced to compact horizontal size class so the inner
    /// TabView renders the iPhone-style bottom tab bar instead of the iPad
    /// floating/top tab bar.
    @ViewBuilder
    private func iPadFloatingPanel(currentHeight: CGFloat, availableHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            iPadDragHandle(availableHeight: availableHeight)
            panelContent
        }
        .frame(width: regularPanelWidth, height: currentHeight)
        .background(sheetSolidBackground)
        .environment(\.horizontalSizeClass, .compact)
        .clipShape(RoundedRectangle(cornerRadius: regularPanelCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 8)
    }

    @ViewBuilder
    private func iPadDragHandle(availableHeight: CGFloat) -> some View {
        Capsule()
            .fill(Color(.systemGray3))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        dragOffset = value.translation.height
                    }
                    .onEnded { value in
                        let base = panelState.iPadHeight(availableHeight: availableHeight)
                        // Use predicted end for velocity-aware snapping.
                        let predictedHeight = base - value.predictedEndTranslation.height
                        let newState = closestState(to: predictedHeight, availableHeight: availableHeight)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            panelState = newState
                            dragOffset = 0
                        }
                    }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Resize panel")
    }

    /// Pick the `PanelState` whose target height is closest to `height`.
    private func closestState(to height: CGFloat, availableHeight: CGFloat) -> PanelState {
        PanelState.allCases.min { lhs, rhs in
            abs(lhs.iPadHeight(availableHeight: availableHeight) - height) <
            abs(rhs.iPadHeight(availableHeight: availableHeight) - height)
        } ?? .low
    }
}
