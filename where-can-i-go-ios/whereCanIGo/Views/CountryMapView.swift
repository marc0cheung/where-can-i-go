import SwiftUI
import MapKit

/// MapKit-backed choropleth of the world. Each country polygon is filled with the
/// color of the matching `VisaCategory` for the currently-selected passport.
struct CountryMapView: UIViewRepresentable {
    @EnvironmentObject var appState: AppState

    func makeCoordinator() -> Coordinator { Coordinator(appState: appState) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.mapType = .mutedStandard
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.showsScale = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false

        // Initial world view
        map.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 20, longitude: 20),
            span: MKCoordinateSpan(latitudeDelta: 140, longitudeDelta: 140)
        ), animated: false)

        context.coordinator.loadGeoJSON(into: map)
        return map
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.appState = appState
        context.coordinator.refreshOverlayColors(on: uiView)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var appState: AppState

        init(appState: AppState) { self.appState = appState }

        func loadGeoJSON(into map: MKMapView) {
            // Accept either filename, since some downloads omit a dot in the extension.
            let url = Bundle.main.url(forResource: "world-countries", withExtension: "geojson")
                   ?? Bundle.main.url(forResource: "world-countries", withExtension: "geo.json")

            guard let url else {
                print("[WhereCanIGo] world-countries.geojson not in bundle. See Resources/GEOJSON_INSTRUCTIONS.txt")
                return
            }

            do {
                let data = try Data(contentsOf: url)
                let features = try MKGeoJSONDecoder().decode(data)
                var overlays: [MKOverlay] = []

                for f in features {
                    guard let feature = f as? MKGeoJSONFeature else { continue }
                    let iso = Self.extractISO3(from: feature.properties)
                    for geometry in feature.geometry {
                        if let polygon = geometry as? MKPolygon {
                            polygon.title = iso
                            overlays.append(polygon)
                        } else if let multi = geometry as? MKMultiPolygon {
                            for p in multi.polygons {
                                p.title = iso
                                overlays.append(p)
                            }
                        }
                    }
                }
                map.addOverlays(overlays)
            } catch {
                print("[WhereCanIGo] GeoJSON parse error: \(error)")
            }
        }

        /// Walks common property keys to find an ISO 3166-1 alpha-3 country code.
        static func extractISO3(from propertiesData: Data?) -> String? {
            guard let data = propertiesData,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            for key in ["ISO_A3", "ISO3166-1-Alpha-3", "iso_a3", "ADM0_A3", "id", "ISO3"] {
                if let value = json[key] as? String, value.count == 3, value != "-99" {
                    return value.uppercased()
                }
            }
            return nil
        }

        func refreshOverlayColors(on map: MKMapView) {
            for overlay in map.overlays {
                guard let polygon = overlay as? MKPolygon,
                      let renderer = map.renderer(for: polygon) as? MKPolygonRenderer else { continue }
                apply(renderer: renderer, for: polygon)
            }
        }

        private func apply(renderer: MKPolygonRenderer, for polygon: MKPolygon) {
            let iso = polygon.title
            let category = iso.flatMap { appState.visaCategory(for: $0) } ?? .visaRequired
            renderer.fillColor = UIColor(category.color).withAlphaComponent(0.85)
            renderer.strokeColor = UIColor.white.withAlphaComponent(0.7)
            renderer.lineWidth = 0.5
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                apply(renderer: renderer, for: polygon)
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
