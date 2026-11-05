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
        return simplifiedRing(coords, tolerance: 0.6)
    }

    private static func simplifiedRing(_ coordinates: [CLLocationCoordinate2D], tolerance: CLLocationDegrees) -> [CLLocationCoordinate2D] {
        guard let first = coordinates.first, let last = coordinates.last, coordinates.count > 4 else { return coordinates }

        let isClosed = first.latitude == last.latitude && first.longitude == last.longitude
        var simplified = ramerDouglasPeucker(isClosed ? Array(coordinates.dropLast()) : coordinates, epsilon: tolerance)
        if isClosed, let first = simplified.first {
            simplified.append(first)
        }
        return simplified.count >= 4 ? simplified : coordinates
    }

    private static func ramerDouglasPeucker(_ points: [CLLocationCoordinate2D], epsilon: CLLocationDegrees) -> [CLLocationCoordinate2D] {
        guard points.count > 2 else { return points }

        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var ranges = [(start: 0, end: points.count - 1)]
        while let range = ranges.popLast() {
            guard range.end - range.start > 1 else { continue }
            var maxDistance: CLLocationDegrees = 0
            var index = range.start
            for i in (range.start + 1)..<range.end {
                let distance = perpendicularDistance(points[i], from: points[range.start], to: points[range.end])
                if distance > maxDistance {
                    maxDistance = distance
                    index = i
                }
            }
            if maxDistance > epsilon {
                keep[index] = true
                ranges.append((range.start, index))
                ranges.append((index, range.end))
            }
        }
        return zip(points, keep).compactMap { $1 ? $0 : nil }
    }

    private static func perpendicularDistance(_ point: CLLocationCoordinate2D,
                                              from start: CLLocationCoordinate2D,
                                              to end: CLLocationCoordinate2D) -> CLLocationDegrees {
        let dx = end.longitude - start.longitude
        let dy = end.latitude - start.latitude

        if dx == 0 && dy == 0 {
            return hypot(point.longitude - start.longitude, point.latitude - start.latitude)
        }

        let numerator = abs(dy * point.longitude - dx * point.latitude + end.longitude * start.latitude - end.latitude * start.longitude)
        return numerator / hypot(dx, dy)
    }
}

/// Flat equirectangular world map that fills visited countries with an accent color.
/// Works inside `ImageRenderer`, which can't capture a live MapKit view.
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
