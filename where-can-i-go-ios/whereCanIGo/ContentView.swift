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
