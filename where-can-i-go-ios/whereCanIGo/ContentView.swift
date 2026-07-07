import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var sheetPresented: Bool = true
    @State private var selectedTab: PanelTab = .overview
    @State private var selectedDetent: PresentationDetent = .height(290)

    var body: some View {
        CountryMapView()
            .ignoresSafeArea()
            .sheet(isPresented: $sheetPresented) {
                VStack(spacing: 0) {
                    SheetHeader()
                        .background(Color.clear)

                    TabView(selection: $selectedTab) {
                        Tab(PanelTab.overview.rawValue,
                            systemImage: "globe.asia.australia.fill",
                            value: PanelTab.overview) {
                            OverviewTab()
                                .background(Color.clear)
                        }

                        Tab(PanelTab.myVisas.rawValue,
                            systemImage: "person.text.rectangle.fill",
                            value: PanelTab.myVisas) {
                            MyVisasTab()
                                .background(Color.clear)
                        }

                        Tab(PanelTab.manageData.rawValue,
                            systemImage: "slider.horizontal.3",
                            value: PanelTab.manageData) {
                            ManageDataTab()
                                .background(Color.clear)
                        }
                    }
                    .background(Color.clear)
                    .scrollContentBackground(.hidden)
                }
                .background(Color.clear)
                .presentationDetents([.height(290), .medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationCornerRadius(55)
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
                .presentationBackground(
                    selectedDetent == .height(290) ? AnyShapeStyle(.ultraThinMaterial)
                                                    : AnyShapeStyle(Color(.systemBackground))
                )
            }
    }
}
