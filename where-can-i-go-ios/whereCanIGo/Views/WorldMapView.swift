import SwiftUI
import MapKit
import CoreLocation

/// Loads & caches simplified country outlines from the bundled GeoJSON,
/// used by the flat abstract overview map (no MapKit rendering needed).
enum WorldShapeStore {
    struct CountryShape {
        let iso: String
        let rings: [[CLLocationCoordinate2D]]
    }

    static let shared: [CountryShape] = load()

    private static func load() -> [CountryShape] {
        let url = Bundle.main.url(forResource: "world-countries", withExtension: "geojson")
            ?? Bundle.main.url(forResource: "world-countries", withExtension: "geo.json")
        guard let url,
              let data = try? Data(contentsOf: url),
              let features = try? MKGeoJSONDecoder().decode(data) else { return [] }

        var result: [CountryShape] = []
        for feature in features.compactMap({ $0 as? MKGeoJSONFeature }) {
            let iso = CountryMapView.Coordinator.extractISO3(from: feature.properties) ?? ""
            var rings: [[CLLocationCoordinate2D]] = []
            for geometry in feature.geometry {
                if let polygon = geometry as? MKPolygon {
                    rings.append(simplified(polygon))
                } else if let multi = geometry as? MKMultiPolygon {
                    for polygon in multi.polygons { rings.append(simplified(polygon)) }
                }
            }
            if !rings.isEmpty { result.append(CountryShape(iso: iso, rings: rings)) }
        }
        return result
    }

    private static func simplified(_ polygon: MKPolygon) -> [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: .init(), count: polygon.pointCount)
        polygon.getCoordinates(&coords, range: NSRange(location: 0, length: polygon.pointCount))
        return CountryMapView.Coordinator.simplifiedRing(coords, tolerance: 0.6)
    }
}

/// Flat equirectangular world map that fills visited countries with an accent color.
/// Renders reliably inside `ImageRenderer` (unlike a live MapKit view).
struct WorldMapView: View {
    let visitedCodes: Set<String>
    var landColor: Color = Color.white.opacity(0.13)
    var visitedColor: Color = Color(red: 0.95, green: 0.61, blue: 0.24)

    // Crop the poles (Antarctica) so the map reads like a travel poster.
    private let latTop: Double = 83
    private let latBottom: Double = -56

    var body: some View {
        Canvas { context, size in
            for shape in WorldShapeStore.shared where !visitedCodes.contains(shape.iso) {
                context.fill(path(for: shape, in: size), with: .color(landColor))
            }
            // Visited countries drawn last so they sit above their neighbors.
            for shape in WorldShapeStore.shared where visitedCodes.contains(shape.iso) {
                context.fill(path(for: shape, in: size), with: .color(visitedColor))
            }
        }
        .aspectRatio(360 / (latTop - latBottom), contentMode: .fit)
    }

    private func path(for shape: WorldShapeStore.CountryShape, in size: CGSize) -> Path {
        var path = Path()
        for ring in shape.rings where ring.count > 2 {
            var isFirst = true
            for coord in ring {
                let point = project(coord, in: size)
                if isFirst { path.move(to: point); isFirst = false }
                else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
        return path
    }

    private func project(_ coord: CLLocationCoordinate2D, in size: CGSize) -> CGPoint {
        let x = (coord.longitude + 180) / 360 * size.width
        let y = (latTop - coord.latitude) / (latTop - latBottom) * size.height
        return CGPoint(x: x, y: y)
    }
}
