import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var sheetPresented: Bool = true
    @State private var selectedTab: PanelTab = .overview

    var body: some View {
        CountryMapView()
            .ignoresSafeArea()
            .sheet(isPresented: $sheetPresented) {
                BottomSheetView(selectedTab: $selectedTab)
                    .presentationDetents([.height(290), .medium, .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .presentationCornerRadius(28)
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled()
            }
    }
}
