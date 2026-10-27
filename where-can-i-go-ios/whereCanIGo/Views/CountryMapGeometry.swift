import MapKit

/// Country outlines prepared at several levels of detail (LOD).
///
/// MapKit renders `MKPolygonRenderer` overlays as GPU vector geometry, so the cost of
/// panning/zooming scales with the number of vertices on screen. Showing the raw
/// GeoJSON (~550k points) while zoomed out both slows tile preparation and makes
/// borders look uneven: sub-pixel zig-zags get stroked on top of each other so jagged
/// borders look thick while smooth borders look thin. Picking a level whose tolerance
/// is below one screen point keeps every border the same visual weight.
nonisolated struct PreparedCountryOverlays: @unchecked Sendable {
    /// Overlays per level, ordered coarse → fine. The last level is the raw geometry.
    let levels: [[MKOverlay]]
    /// Simplification tolerance (in map points) used for each entry of `levels`.
    let tolerances: [Double]

    var finest: [MKOverlay] { levels.last ?? [] }
}

nonisolated enum CountryGeometry {
    /// Tolerances in degrees of longitude, coarse → fine; `0` keeps the raw data.
    static let toleranceDegrees: [Double] = [0.2, 0.06, 0.02, 0.006, 0]

    static func mapPoints(fromDegrees degrees: Double) -> Double {
        degrees * MKMapSize.world.width / 360
    }

    static func prepare(features: [MKGeoJSONObject]) -> PreparedCountryOverlays {
        let tolerances = toleranceDegrees.map(mapPoints(fromDegrees:))
        var levels = [[MKOverlay]](repeating: [], count: tolerances.count)

        for object in features {
            guard let feature = object as? MKGeoJSONFeature else { continue }
            let iso = CountryMapView.Coordinator.extractISO3(from: feature.properties)
            for geometry in feature.geometry {
                let polygons: [MKPolygon]
                if let polygon = geometry as? MKPolygon {
                    polygons = [polygon]
                } else if let multi = geometry as? MKMultiPolygon {
                    polygons = multi.polygons
                } else {
                    continue
                }
                guard !polygons.isEmpty else { continue }
                let largest = polygons.max { area(of: $0.boundingMapRect) < area(of: $1.boundingMapRect) }

                for (index, tolerance) in tolerances.enumerated() {
                    let shape: MKShape & MKOverlay
                    if tolerance == 0 {
                        shape = geometry as! MKShape & MKOverlay
                    } else {
                        let parts = polygons.compactMap { polygon in
                            simplified(polygon, tolerance: tolerance, keepTiny: polygon === largest)
                        }
                        guard !parts.isEmpty else { continue }
                        shape = parts.count == 1 ? parts[0] : MKMultiPolygon(parts)
                    }
                    shape.title = iso
                    levels[index].append(shape)
                }
            }
        }
        return PreparedCountryOverlays(levels: levels, tolerances: tolerances)
    }

    /// Simplifies a polygon in Mercator map-point space (so the tolerance maps to a
    /// constant on-screen distance at every latitude). Rings smaller than the tolerance
    /// are invisible at that zoom and are dropped, unless `keepTiny` is set so that
    /// micro-states and small islands nations never disappear.
    static func simplified(_ polygon: MKPolygon, tolerance: Double, keepTiny: Bool) -> MKPolygon? {
        let rect = polygon.boundingMapRect
        if !keepTiny && max(rect.width, rect.height) < tolerance { return nil }

        let outer = simplifiedRing(points(of: polygon), tolerance: tolerance)
        let holes = (polygon.interiorPolygons ?? []).compactMap {
            simplified($0, tolerance: tolerance, keepTiny: false)
        }
        return outer.withUnsafeBufferPointer {
            MKPolygon(points: $0.baseAddress!, count: $0.count, interiorPolygons: holes.isEmpty ? nil : holes)
        }
    }

    static func points(of multiPoint: MKMultiPoint) -> [MKMapPoint] {
        Array(UnsafeBufferPointer(start: multiPoint.points(), count: multiPoint.pointCount))
    }

    /// Ramer–Douglas–Peucker on a closed ring. Falls back to the original ring when the
    /// result would degenerate (fewer than 3 distinct vertices).
    static func simplifiedRing(_ ring: [MKMapPoint], tolerance: Double) -> [MKMapPoint] {
        guard ring.count > 4 else { return ring }
        var points = ring
        if let first = points.first, let last = points.last, first.x == last.x, first.y == last.y {
            points.removeLast()
        }

        // Split the closed ring at the vertex farthest from the first one so both
        // halves are open chains with distinct endpoints.
        var split = 0
        var farthest = -1.0
        for i in 1..<points.count {
            let d = squaredDistance(points[i], points[0])
            if d > farthest { farthest = d; split = i }
        }
        guard split > 0 else { return ring }

        var keep = [Bool](repeating: false, count: points.count + 1)
        let closed = points + [points[0]]
        keep[0] = true
        keep[split] = true
        keep[closed.count - 1] = true
        markRDP(closed, from: 0, to: split, tolerance: tolerance, keep: &keep)
        markRDP(closed, from: split, to: closed.count - 1, tolerance: tolerance, keep: &keep)

        var result: [MKMapPoint] = []
        result.reserveCapacity(64)
        for i in closed.indices where keep[i] { result.append(closed[i]) }
        return result.count >= 4 ? result : ring
    }

    private static func markRDP(_ points: [MKMapPoint], from start: Int, to end: Int,
                                tolerance: Double, keep: inout [Bool]) {
        var stack = [(start, end)]
        while let (a, b) = stack.popLast() {
            guard b > a + 1 else { continue }
            var maxDistance = -1.0
            var index = a
            for i in (a + 1)..<b {
                let d = segmentDistance(points[i], points[a], points[b])
                if d > maxDistance { maxDistance = d; index = i }
            }
            if maxDistance > tolerance {
                keep[index] = true
                stack.append((a, index))
                stack.append((index, b))
            }
        }
    }

    private static func segmentDistance(_ p: MKMapPoint, _ a: MKMapPoint, _ b: MKMapPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return squaredDistance(p, a).squareRoot() }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    private static func squaredDistance(_ a: MKMapPoint, _ b: MKMapPoint) -> Double {
        (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
    }

    static func area(of rect: MKMapRect) -> Double { rect.width * rect.height }

    /// A point guaranteed to be inside the polygon and visually near its middle.
    /// The bounding-box center is used when it falls inside the shape; otherwise (e.g.
    /// crescent-shaped Croatia, or South Africa whose center is in Lesotho) the
    /// midpoint of the widest horizontal interior span is used.
    static func visualCenter(of polygon: MKPolygon) -> MKMapPoint {
        let rect = polygon.boundingMapRect
        let center = MKMapPoint(x: rect.midX, y: rect.midY)
        let rings = [points(of: polygon)] + (polygon.interiorPolygons ?? []).map { points(of: $0) }

        func crossings(atY y: Double) -> [Double] {
            var xs: [Double] = []
            for ring in rings where ring.count > 1 {
                var a = ring[ring.count - 1]
                for b in ring {
                    if (a.y > y) != (b.y > y) {
                        xs.append(a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y))
                    }
                    a = b
                }
            }
            return xs.sorted()
        }

        let centerCrossings = crossings(atY: center.y)
        if centerCrossings.filter({ $0 < center.x }).count % 2 == 1 { return center }

        var best: (width: Double, point: MKMapPoint)?
        for fraction in [0.5, 0.4, 0.6, 0.3, 0.7, 0.2, 0.8] {
            let y = rect.minY + rect.height * fraction
            let xs = crossings(atY: y)
            var i = 0
            while i + 1 < xs.count {
                let width = xs[i + 1] - xs[i]
                if width > (best?.width ?? 0) {
                    best = (width, MKMapPoint(x: (xs[i] + xs[i + 1]) / 2, y: y))
                }
                i += 2
            }
        }
        return best?.point ?? center
    }
}

actor CountryOverlayStore {
    static let shared = CountryOverlayStore()
    private var cached: PreparedCountryOverlays?

    func load(from url: URL) throws -> PreparedCountryOverlays {
        if let cached { return cached }
        let data = try Data(contentsOf: url)
        let features = try MKGeoJSONDecoder().decode(data)
        let prepared = CountryGeometry.prepare(features: features)
        cached = prepared
        return prepared
    }
}
