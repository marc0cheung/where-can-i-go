import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var friendStore: FriendStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: PanelTab = .overview
    @State private var panelState: PanelState = .low
    @State private var selectedDiceContinents: Set<Continent> = []
    @State private var selectedDiceAirlines: Set<String> = []
    @State private var diceIncludesAllEntryRequirements = false
    @State private var isMapLoading = true
    @State private var wishlistCountry: Country?
    @State private var policyCountry: Country?
    /// Live drag delta while the user is dragging the iPad panel handle.
    /// Positive = drag down (panel shrinks). Reset to 0 on release.
    @State private var dragOffset: CGFloat = 0
    /// Width of the trailing system strip inside the compact sheet (0 when absent).
    @State private var sideStripWidth: CGFloat = 0
    /// Height of the sheet header in side-strip mode, where it overlays the tab view.
    @State private var sideStripHeaderHeight: CGFloat = 0

    // Set to true to compare the original Manage Data tab with the integrated flow.
    private let showsManageDataTab = false

    // Regular size class (iPad / wide window) floating-panel metrics.
    private let regularPanelWidth: CGFloat = 390
    private let regularPanelSideInset: CGFloat = 16
    private let regularPanelBottomInset: CGFloat = 24
    private let regularPanelCornerRadius: CGFloat = 30
    private let regularPanelMinHeight: CGFloat = 220

    private var isRegularWidth: Bool { horizontalSizeClass == .regular }

    /// Compact windows with a large trailing safe-area inset reserve a side
    /// strip for system UI (e.g. iPhone Duo outer display). The sheet body
    /// respects that inset, leaving the strip transparent over the map, and the
    /// system tab bar lays itself out vertically inside the strip.
    /// Landscape iPhones are excluded: their horizontal insets are symmetric.
    private func hasSideStrip(_ proxy: GeometryProxy) -> Bool {
        let insets = proxy.safeAreaInsets
        return !isRegularWidth && insets.trailing > 20 && insets.leading < 1
    }

    private var sheetSolidBackground: Color {
        Color(.systemBackground)
    }

    /// Shared content used both inside the compact-width system sheet and the
    /// regular-width floating panel, so behavior stays identical across modes.
    @ViewBuilder
    private func panelContent(sideStrip: Bool = false) -> some View {
        if sideStrip {
            sideStripPanel
        } else {
            panelBody(sideStrip: false)
                .background(sheetSolidBackground)
        }
    }

    /// Side-strip layout: the sheet itself is clear, and its body draws its
    /// background only inside the safe area, left of the strip.
    private var sideStripPanel: some View {
        panelBody(sideStrip: true)
            .background {
                RoundedRectangle(cornerRadius: sheetCornerRadius, style: .continuous)
                    .fill(sheetSolidBackground)
                    .ignoresSafeArea(.container, edges: .bottom)
            }
            .overlay(alignment: .top) { sideStripDragIndicator }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.trailing } action: {
                sideStripWidth = $0
            }
            .environment(\.sideStripWidth, sideStripWidth)
    }

    /// Replaces the system indicator, which centres on the full sheet width.
    private var sideStripDragIndicator: some View {
        Capsule()
            .fill(Color(.tertiaryLabel))
            .frame(width: 36, height: 5)
            .padding(.top, 5)
            .accessibilityElement()
            .accessibilityLabel("Resize panel")
            .accessibilityAdjustableAction { direction in
                let states = PanelState.allCases
                guard let index = states.firstIndex(of: panelState) else { return }
                switch direction {
                case .increment: panelState = states[min(index + 1, states.count - 1)]
                case .decrement: panelState = states[max(index - 1, 0)]
                @unknown default: break
                }
            }
    }

    private let sheetCornerRadius: CGFloat = 55

    @ViewBuilder
    private func tabContent(_ tab: PanelTab, sideStrip: Bool) -> some View {
        if isRegularWidth {
            // Lists extend beneath the native glass bar unless clipped to their safe-area layout.
            tabRoot(tab)
                .clipped()
        } else {
            tabRoot(tab)
                .modifier(SideStripTabContentLayout(
                    isEnabled: sideStrip, topInset: sideStripHeaderHeight, cornerRadius: sheetCornerRadius))
        }
    }

    @ViewBuilder
    private func tabRoot(_ tab: PanelTab) -> some View {
        switch tab {
        case .overview:
            OverviewTab { code in
                appState.selectCountry(code: code)
                appState.diceSpinTarget = code
                withAnimation(.smooth(duration: 0.25)) { panelState = .low }
            }
        case .myVisas:
            MyVisasTab()
        case .myTravels:
            MyTravelsTab()
        case .manageData:
            ManageDataTab()
        }
    }

    private var sheetHeader: some View {
        SheetHeader(
            panelState: $panelState,
            selectedDiceContinents: $selectedDiceContinents,
            selectedDiceAirlines: $selectedDiceAirlines,
            diceIncludesAllEntryRequirements: $diceIncludesAllEntryRequirements,
            isFloatingPanel: isRegularWidth
        )
    }

    private func panelTabs(sideStrip: Bool) -> some View {
        TabView(selection: $selectedTab) {
            Tab(PanelTab.overview.localizedTitle,
                systemImage: PanelTab.overview.systemImage,
                value: PanelTab.overview) {
                tabContent(.overview, sideStrip: sideStrip)
            }

            Tab(PanelTab.myVisas.localizedTitle,
                systemImage: PanelTab.myVisas.systemImage,
                value: PanelTab.myVisas) {
                tabContent(.myVisas, sideStrip: sideStrip)
            }

            Tab(PanelTab.myTravels.localizedTitle,
                systemImage: PanelTab.myTravels.systemImage,
                value: PanelTab.myTravels) {
                tabContent(.myTravels, sideStrip: sideStrip)
            }

            if showsManageDataTab {
                Tab(PanelTab.manageData.localizedTitle,
                    systemImage: PanelTab.manageData.systemImage,
                    value: PanelTab.manageData) {
                    tabContent(.manageData, sideStrip: sideStrip)
                }
            }
        }
        .toolbarBackground(sheetSolidBackground, for: .tabBar)
        // In the side strip the tab bar floats as Liquid Glass over the map.
        .toolbarBackground(sideStrip ? .hidden : .visible, for: .tabBar)
    }

    @ViewBuilder
    private func panelBody(sideStrip: Bool) -> some View {
        Group {
            if sideStrip {
                // The TabView spans the full sheet height so the vertical tab bar
                // in the strip keeps room for all its buttons at the low detent;
                // the tab content starts below the overlaid header.
                panelTabs(sideStrip: true)
                    .overlay(alignment: .top) {
                        sheetHeader
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                                sideStripHeaderHeight = $0
                            }
                    }
            } else {
                VStack(spacing: 0) {
                    sheetHeader
                    panelTabs(sideStrip: false)
                }
            }
        }
        .sheet(item: $wishlistCountry) { country in
            CountryPlansSheet(country: country)
        }
        .sheet(item: $policyCountry) { country in
            EntryPolicySheet(
                country: country,
                existingEntry: appState.data.defaultVisas.first { $0.countryCode == country.code },
                existingPersonalVisa: appState.data.personalVisas.first { $0.countryCode == country.code }
            )
        }
    }

    /// Bridge `PanelState` to the system sheet's `PresentationDetent` binding
    /// so the compact-width sheet keeps its native drag-to-resize behavior.
    private func detentBinding(sideStrip: Bool) -> Binding<PresentationDetent> {
        Binding(
            get: { panelState.presentationDetent(sideStrip: sideStrip) },
            set: { panelState = PanelState.from(detent: $0) }
        )
    }

    var body: some View {
        GeometryReader { proxy in
            CountryMapView(onGeometryLoaded: { isMapLoading = false })
                .ignoresSafeArea()
                .overlay(alignment: .top) {
                    if isMapLoading {
                        ProgressView("Loading…")
                            .padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .padding(.top, 16)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if isRegularWidth {
                        regularWidthOverlay(availableHeight: proxy.size.height)
                    }
                }
                .overlay(alignment: .bottom) {
                    if !isRegularWidth,
                       let code = appState.selectedCountryCode,
                       let country = appState.country(for: code) {
                        countryDetailCard(code: code, country: country)
                            .padding(.bottom, hasSideStrip(proxy) ? PanelState.sideStripLowHeight + 20 : 310)
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
                // Visibility is derived from layout, not UIKit's dismissal write-back
                // when a fold transition replaces the sheet with the floating panel.
                .sheet(isPresented: .constant(!isRegularWidth)) {
                    let sideStrip = hasSideStrip(proxy)
                    panelContent(sideStrip: sideStrip)
                        .presentationDetents(PanelState.detents(sideStrip: sideStrip), selection: detentBinding(sideStrip: sideStrip))
                        .presentationBackgroundInteraction(
                            .enabled(upThrough: PanelState.medium.presentationDetent(sideStrip: sideStrip)))
                        .presentationCornerRadius(sheetCornerRadius)
                        .presentationDragIndicator(sideStrip ? .hidden : .visible)
                        .interactiveDismissDisabled()
                        .presentationBackground(sideStrip ? Color.clear : sheetSolidBackground)
                        .background(ClearSheetBackgroundEffect(isEnabled: sideStrip))
                }
        }
        .onAppear {
            appState.refreshVisaValidity()
            showIncomingCard(friendStore.incomingCardURL)
        }
        .onChange(of: friendStore.incomingCardURL) { _, url in
            showIncomingCard(url)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { appState.refreshVisaValidity() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            appState.refreshVisaValidity()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            appState.refreshVisaValidity()
        }
    }

    private func countryDetailCard(code: String, country: Country) -> some View {
        CountryDetailCard(
            countryCode: code, selectedTab: $selectedTab, panelState: $panelState,
            onReviewWishlist: { wishlistCountry = country },
            onShowPolicy: { policyCountry = country }
        )
    }

    /// Opens the Travels tab so the Friends screen can handle an opened card file.
    private func showIncomingCard(_ url: URL?) {
        guard url != nil else { return }
        selectedTab = .myTravels
        appState.selectedCountryCode = nil
        withAnimation(.smooth(duration: 0.25)) { panelState = .high }
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
               let country = appState.country(for: code) {
                countryDetailCard(code: code, country: country)
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
    /// TabView uses the iPhone-style bottom tab bar on iPad too.
    @ViewBuilder
    private func iPadFloatingPanel(currentHeight: CGFloat, availableHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            iPadDragHandle(availableHeight: availableHeight)
            panelContent()
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
