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

        // Use a globe-capable style so zooming out transitions into 3D Earth.
        if #available(iOS 16.0, *) {
            map.preferredConfiguration = MKHybridMapConfiguration(
                elevationStyle: .realistic
            )
        } else {
            map.mapType = .mutedStandard
        }

        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.showsScale = false
        map.isRotateEnabled = true
        map.isPitchEnabled = true

        // Keep the map unconstrained so users can continuously zoom out.
        map.setCameraBoundary(nil, animated: false)
        map.setCameraZoomRange(nil, animated: false)

        // Initialize with camera distance (instead of region) for globe-friendly behavior.
        let worldCamera = MKMapCamera(
            lookingAtCenter: CLLocationCoordinate2D(latitude: 20, longitude: 20),
            fromDistance: 35_000_000,
            pitch: 0,
            heading: 0
        )
        map.setCamera(worldCamera, animated: false)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        map.addGestureRecognizer(tap)

        context.coordinator.loadGeoJSON(into: map)
        return map
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        context.coordinator.appState = appState
        context.coordinator.refreshOverlayColors(on: uiView)
        context.coordinator.handleDiceSpinTargetIfNeeded(appState.diceSpinTarget, in: uiView)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var appState: AppState

        private enum OverlayDetail {
            case low
            case high
        }

        private var lastDataSignature: Int? = nil
        private var lastSelectedCode: String? = nil
        private var categoryByISO3: [String: VisaCategory] = [:]
        private var rendererCache: [ObjectIdentifier: MKOverlayPathRenderer] = [:]
        private var highDetailOverlays: [MKOverlay] = []
        private var lowDetailOverlays: [MKOverlay] = []
        private var currentDetail: OverlayDetail = .low

        // Hysteresis prevents rapid back-and-forth switching near threshold.
        private let lowToHighLatitudeDelta: CLLocationDegrees = 28
        private let highToLowLatitudeDelta: CLLocationDegrees = 40
        private let lowDetailTolerance: CLLocationDegrees = 0.22

        // MARK: - Dice spin state
        private var lastDiceSpinTarget: String? = nil
        private var spinTimer: Timer?
        private var spinStartTime: Date = .now
        private let spinDuration: TimeInterval = 2.5
        private var spinStartLon: Double = 0
        private var spinStartLat: Double = 20
        private var spinStartDistance: Double = 35_000_000
        private var spinEndCoordinate: CLLocationCoordinate2D = .init(latitude: 20, longitude: 20)
        private let spinEndDistance: Double = 12_000_000
        private var spinTotalLonTravel: Double = 0
        private var spinTargetCode: String = ""
        private var spinEndCameraLat: Double = 20
        private weak var spinMapView: MKMapView?

        /// How many degrees south the camera center is offset from the target country,
        /// so the country appears above the CountryDetailCard rather than behind it.
        private let spinCameraLatOffset: Double = -18.0

        init(appState: AppState) { self.appState = appState }

        // MARK: - Dice spin animation

        /// Computes the centroid of the named country from already-loaded GeoJSON overlays.
        func centroid(for isoCode: String) -> CLLocationCoordinate2D? {
            let all = highDetailOverlays.isEmpty ? lowDetailOverlays : highDetailOverlays
            let matching = all.filter { ($0 as? MKShape)?.title == isoCode }
            guard !matching.isEmpty else { return nil }

            var unionRect = matching[0].boundingMapRect
            for overlay in matching.dropFirst() {
                unionRect = unionRect.union(overlay.boundingMapRect)
            }
            return MKMapPoint(x: unionRect.midX, y: unionRect.midY).coordinate
        }

        /// Called from `updateUIView` whenever `appState.diceSpinTarget` may have changed.
        func handleDiceSpinTargetIfNeeded(_ target: String?, in mapView: MKMapView) {
            if let target {
                guard target != lastDiceSpinTarget else { return }
                lastDiceSpinTarget = target
                if let coordinate = centroid(for: target) {
                    startSpinAnimation(to: coordinate, targetCode: target, in: mapView)
                } else {
                    // No GeoJSON data for this code — fall back to instant select.
                    appState.selectCountry(code: target)
                    appState.diceSpinTarget = nil
                    lastDiceSpinTarget = nil
                }
            } else {
                lastDiceSpinTarget = nil
            }
        }

        private func startSpinAnimation(to coordinate: CLLocationCoordinate2D,
                                        targetCode: String,
                                        in mapView: MKMapView) {
            spinTimer?.invalidate()

            let cam = mapView.camera
            spinStartTime = Date()
            spinStartLon = cam.centerCoordinate.longitude
            spinStartLat = cam.centerCoordinate.latitude
            spinStartDistance = cam.altitude
            spinEndCoordinate = coordinate
            // Bias the camera's final latitude southward so the country appears
            // above the CountryDetailCard rather than behind it.
            spinEndCameraLat = min(max(coordinate.latitude + spinCameraLatOffset, -75), 75)
            spinTargetCode = targetCode
            spinMapView = mapView

            // Shortest-path longitude delta, then add two full rotations for the spin effect.
            var lonDelta = coordinate.longitude - spinStartLon
            while lonDelta > 180  { lonDelta -= 360 }
            while lonDelta < -180 { lonDelta += 360 }
            spinTotalLonTravel = 2 * 360 + lonDelta

            spinTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.spinTick()
            }
        }

        private func spinTick() {
            guard let mapView = spinMapView else { spinTimer?.invalidate(); return }

            let elapsed = Date().timeIntervalSince(spinStartTime)
            let t = min(elapsed / spinDuration, 1.0)

            // Ease-out cubic: fast start → smooth deceleration → precise stop.
            let ease = 1.0 - pow(1.0 - t, 3.0)

            let lon      = spinStartLon + spinTotalLonTravel * ease
            let lat      = spinStartLat + (spinEndCameraLat - spinStartLat) * ease
            let distance = spinStartDistance + (spinEndDistance - spinStartDistance) * ease

            // MKMapCamera requires longitude in [-180, 180]; wrap the accumulated value.
            var wrappedLon = lon.truncatingRemainder(dividingBy: 360)
            if wrappedLon > 180  { wrappedLon -= 360 }
            if wrappedLon < -180 { wrappedLon += 360 }

            let camera = MKMapCamera(
                lookingAtCenter: CLLocationCoordinate2D(latitude: lat, longitude: wrappedLon),
                fromDistance: max(distance, 1_000_000),
                pitch: 0,
                heading: 0
            )
            mapView.setCamera(camera, animated: false)

            guard t >= 1.0 else { return }
            spinTimer?.invalidate()
            spinTimer = nil
            appState.selectCountry(code: spinTargetCode)
            appState.diceSpinTarget = nil
        }

        // MARK: - Tap handling

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let mapView = recognizer.view as? MKMapView else { return }
            let touchPoint = recognizer.location(in: mapView)
            let coordinate = mapView.convert(touchPoint, toCoordinateFrom: mapView)
            let mapPoint = MKMapPoint(coordinate)
            let tappedISO = hitTest(mapPoint: mapPoint, in: mapView)

            Task { @MainActor in
                if let code = tappedISO, code == appState.selectedCountryCode {
                    appState.selectCountry(code: nil)
                } else {
                    appState.selectCountry(code: tappedISO)
                }
            }
        }

        private func hitTest(mapPoint: MKMapPoint, in mapView: MKMapView) -> String? {
            var bestISO: String? = nil
            var bestArea: Double = .infinity

            for overlay in mapView.overlays {
                let key = ObjectIdentifier(overlay)
                guard let renderer = rendererCache[key] else { continue }
                let rendererPoint = renderer.point(for: mapPoint)

                let hit: Bool
                if let pr = renderer as? MKPolygonRenderer {
                    hit = pr.path?.contains(rendererPoint) == true
                } else if let mr = renderer as? MKMultiPolygonRenderer {
                    hit = mr.path?.contains(rendererPoint) == true
                } else {
                    continue
                }

                guard hit else { continue }
                let rect = overlay.boundingMapRect
                let area = rect.size.width * rect.size.height
                if area < bestArea {
                    bestArea = area
                    bestISO = (overlay as? MKShape)?.title ?? nil
                }
            }
            return bestISO
        }

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
                var highOverlays: [MKOverlay] = []
                var lowOverlays: [MKOverlay] = []

                for f in features {
                    guard let feature = f as? MKGeoJSONFeature else { continue }
                    let iso = Self.extractISO3(from: feature.properties)
                    for geometry in feature.geometry {
                        if let polygon = geometry as? MKPolygon {
                            polygon.title = iso
                            highOverlays.append(polygon)

                            let simplified = Self.simplified(polygon: polygon, tolerance: lowDetailTolerance)
                            simplified.title = iso
                            lowOverlays.append(simplified)
                        } else if let multi = geometry as? MKMultiPolygon {
                            multi.title = iso
                            highOverlays.append(multi)

                            let simplified = Self.simplified(multiPolygon: multi, tolerance: lowDetailTolerance)
                            simplified.title = iso
                            lowOverlays.append(simplified)
                        }
                    }
                }

                highDetailOverlays = highOverlays
                lowDetailOverlays = lowOverlays
                currentDetail = map.region.span.latitudeDelta > highToLowLatitudeDelta ? .low : .high

                map.addOverlays(currentDetail == .low ? lowDetailOverlays : highDetailOverlays)
                refreshOverlayColors(on: map)
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
            updateOverlayDetailIfNeeded(on: map)

            let newSelected = appState.selectedCountryCode
            let selectionChanged = newSelected != lastSelectedCode

            let signature = Self.dataSignature(for: appState)
            let dataChanged = signature != lastDataSignature

            guard dataChanged || selectionChanged else { return }

            if dataChanged {
                lastDataSignature = signature
                categoryByISO3 = Self.buildCategoryLookup(from: appState)
                for overlay in map.overlays {
                    let key = ObjectIdentifier(overlay)
                    guard let renderer = rendererCache[key] else { continue }
                    apply(renderer: renderer, for: overlay)
                    renderer.setNeedsDisplay()
                }
            } else {
                // Selection-only change: only redraw previously-selected and newly-selected overlays.
                let codesToRedraw = Set([lastSelectedCode, newSelected].compactMap { $0 })
                for overlay in map.overlays {
                    guard let iso = (overlay as? MKShape)?.title,
                          codesToRedraw.contains(iso) else { continue }
                    let key = ObjectIdentifier(overlay)
                    guard let renderer = rendererCache[key] else { continue }
                    apply(renderer: renderer, for: overlay)
                    renderer.setNeedsDisplay()
                }
            }

            lastSelectedCode = newSelected
        }

        private func apply(renderer: MKOverlayPathRenderer, for overlay: MKOverlay) {
            let iso = (overlay as? MKShape)?.title ?? nil
            let category = iso.flatMap { categoryByISO3[$0] } ?? .visaRequired
            let isSelected = iso != nil && iso == appState.selectedCountryCode
            if isSelected {
                renderer.fillColor = UIColor(category.color).withAlphaComponent(1.0)
                renderer.strokeColor = UIColor.label
                renderer.lineWidth = 2.5
            } else {
                renderer.fillColor = UIColor(category.color).withAlphaComponent(0.85)
                renderer.strokeColor = UIColor.white.withAlphaComponent(0.7)
                renderer.lineWidth = 0.5
            }
        }

        private func updateOverlayDetailIfNeeded(on map: MKMapView) {
            guard !highDetailOverlays.isEmpty, !lowDetailOverlays.isEmpty else { return }

            let nextDetail: OverlayDetail
            switch currentDetail {
            case .low:
                nextDetail = map.region.span.latitudeDelta > lowToHighLatitudeDelta ? .low : .high
            case .high:
                nextDetail = map.region.span.latitudeDelta > highToLowLatitudeDelta ? .low : .high
            }

            guard nextDetail != currentDetail else { return }
            currentDetail = nextDetail

            map.removeOverlays(map.overlays)
            map.addOverlays(currentDetail == .low ? lowDetailOverlays : highDetailOverlays)
            lastDataSignature = nil  // force full re-apply after swap
        }

        static func simplified(multiPolygon: MKMultiPolygon, tolerance: CLLocationDegrees) -> MKMultiPolygon {
            let polygons = multiPolygon.polygons.map { simplified(polygon: $0, tolerance: tolerance) }
            return MKMultiPolygon(polygons)
        }

        static func simplified(polygon: MKPolygon, tolerance: CLLocationDegrees) -> MKPolygon {
            let outer = simplifiedRing(coordinates(of: polygon), tolerance: tolerance)
            let simplifiedInteriorPolygons = (polygon.interiorPolygons ?? []).map {
                simplified(polygon: $0, tolerance: tolerance)
            }

            guard outer.count >= 4 else { return polygon }
            return MKPolygon(coordinates: outer, count: outer.count, interiorPolygons: simplifiedInteriorPolygons)
        }

        static func coordinates(of polygon: MKPolygon) -> [CLLocationCoordinate2D] {
            var coordinates = [CLLocationCoordinate2D](
                repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                count: polygon.pointCount
            )
            polygon.getCoordinates(&coordinates, range: NSRange(location: 0, length: polygon.pointCount))
            return coordinates
        }

        static func simplifiedRing(_ coordinates: [CLLocationCoordinate2D], tolerance: CLLocationDegrees) -> [CLLocationCoordinate2D] {
            guard coordinates.count > 4 else { return coordinates }

            let isClosed = {
                guard let first = coordinates.first, let last = coordinates.last else { return false }
                return coordinatesEqual(first, last)
            }()
            var ring = coordinates
            if isClosed {
                ring.removeLast()
            }

            var simplified = ramerDouglasPeucker(points: ring, epsilon: tolerance)

            if isClosed, let first = simplified.first {
                simplified.append(first)
            }

            return simplified.count >= 4 ? simplified : coordinates
        }

        static func coordinatesEqual(_ lhs: CLLocationCoordinate2D, _ rhs: CLLocationCoordinate2D) -> Bool {
            lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
        }

        static func ramerDouglasPeucker(points: [CLLocationCoordinate2D], epsilon: CLLocationDegrees) -> [CLLocationCoordinate2D] {
            guard points.count > 2 else { return points }

            let start = points[0]
            let end = points[points.count - 1]
            var maxDistance: CLLocationDegrees = 0
            var index = 0

            for i in 1..<(points.count - 1) {
                let distance = perpendicularDistance(points[i], from: start, to: end)
                if distance > maxDistance {
                    maxDistance = distance
                    index = i
                }
            }

            if maxDistance > epsilon {
                let left = ramerDouglasPeucker(points: Array(points[0...index]), epsilon: epsilon)
                let right = ramerDouglasPeucker(points: Array(points[index...]), epsilon: epsilon)
                return Array(left.dropLast()) + right
            }

            return [start, end]
        }

        static func perpendicularDistance(_ point: CLLocationCoordinate2D,
                                          from start: CLLocationCoordinate2D,
                                          to end: CLLocationCoordinate2D) -> CLLocationDegrees {
            let dx = end.longitude - start.longitude
            let dy = end.latitude - start.latitude

            if dx == 0 && dy == 0 {
                return hypot(point.longitude - start.longitude, point.latitude - start.latitude)
            }

            let numerator = abs(dy * point.longitude - dx * point.latitude + end.longitude * start.latitude - end.latitude * start.longitude)
            let denominator = hypot(dx, dy)
            return numerator / denominator
        }

        static func dataSignature(for appState: AppState) -> Int {
            var hasher = Hasher()
            hasher.combine(appState.data.passportCode)
            for entry in appState.data.defaultVisas {
                hasher.combine(entry.countryCode)
                hasher.combine(entry.category)
                hasher.combine(entry.duration)
            }
            for visa in appState.data.personalVisas {
                hasher.combine(visa.id)
                hasher.combine(visa.countryCode)
                hasher.combine(visa.visaType)
                hasher.combine(visa.duration)
                hasher.combine(visa.expiryDate.timeIntervalSince1970)
                hasher.combine(visa.notes)
            }
            return hasher.finalize()
        }

        static func buildCategoryLookup(from appState: AppState) -> [String: VisaCategory] {
            var result: [String: VisaCategory] = [:]

            for entry in appState.data.defaultVisas {
                result[entry.countryCode] = entry.category
            }

            for visa in appState.data.personalVisas {
                result[visa.countryCode] = .myVisa
            }

            return result
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                rendererCache[ObjectIdentifier(overlay)] = renderer
                apply(renderer: renderer, for: overlay)
                return renderer
            }
            if let multiPolygon = overlay as? MKMultiPolygon {
                let renderer = MKMultiPolygonRenderer(multiPolygon: multiPolygon)
                rendererCache[ObjectIdentifier(overlay)] = renderer
                apply(renderer: renderer, for: overlay)
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, didRemove overlays: [any MKOverlay]) {
            for overlay in overlays {
                rendererCache.removeValue(forKey: ObjectIdentifier(overlay))
            }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            updateOverlayDetailIfNeeded(on: mapView)
        }
    }
}
