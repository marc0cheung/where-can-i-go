import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var sheetPresented: Bool = true
    @State private var selectedTab: PanelTab = .overview
    @State private var selectedDetent: PresentationDetent = .height(290)

    private var sheetSolidBackground: Color {
        Color(.systemBackground)
    }

    var body: some View {
        CountryMapView()
            .ignoresSafeArea()
            .overlay(alignment: .bottom) {
                if let code = appState.selectedCountryCode,
                   appState.country(for: code) != nil {
                    CountryDetailCard(countryCode: code, selectedTab: $selectedTab, selectedDetent: $selectedDetent)
                        .padding(.bottom, 310)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.25), value: appState.selectedCountryCode)
            .onChange(of: appState.selectedCountryCode) { _, newCode in
                if newCode != nil {
                    withAnimation(.smooth(duration: 0.25)) { selectedDetent = .height(290) }
                }
            }
            .sheet(isPresented: $sheetPresented) {
                VStack(spacing: 0) {
                    SheetHeader()

                    TabView(selection: $selectedTab) {
                        Tab(PanelTab.overview.rawValue,
                            systemImage: "globe.asia.australia.fill",
                            value: PanelTab.overview) {
                            OverviewTab()
                        }

                        Tab(PanelTab.myVisas.rawValue,
                            systemImage: "person.text.rectangle.fill",
                            value: PanelTab.myVisas) {
                            MyVisasTab()
                        }

                        Tab(PanelTab.manageData.rawValue,
                            systemImage: "slider.horizontal.3",
                            value: PanelTab.manageData) {
                            ManageDataTab()
                        }
                    }
                    .toolbarBackground(sheetSolidBackground, for: .tabBar)
                    .toolbarBackground(.visible, for: .tabBar)
                }
                .background(sheetSolidBackground)
                .presentationDetents([.height(290), .medium, .large], selection: $selectedDetent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationCornerRadius(55)
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
                .presentationBackground(sheetSolidBackground)
            }
    }
}
