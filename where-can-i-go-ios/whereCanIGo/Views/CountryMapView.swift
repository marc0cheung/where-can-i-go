import SwiftUI
import MapKit

/// MapKit-backed choropleth of the world. Each country polygon is filled with the
/// color of the matching `VisaCategory` for the currently-selected passport.
struct CountryMapView: UIViewRepresentable {
    @EnvironmentObject var appState: AppState
    var onGeometryLoaded: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState, onGeometryLoaded: onGeometryLoaded)
    }

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
        context.coordinator.onGeometryLoaded = onGeometryLoaded
        context.coordinator.refreshOverlayColors(on: uiView)
        context.coordinator.handleDiceSpinTargetIfNeeded(appState.diceSpinTarget, in: uiView)
    }

    static func dismantleUIView(_ uiView: MKMapView, coordinator: Coordinator) {
        coordinator.stop()
        uiView.delegate = nil
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var appState: AppState
        var onGeometryLoaded: () -> Void
        private var geometryTask: Task<Void, Never>?
        private var isLoadingGeometry = true

        private var lastVisaSignature: Int? = nil
        private var lastVisitSignature: Int? = nil
        private var lastSelectedCode: String? = nil
        private var categoryByISO3: [String: VisaCategory] = [:]
        private var visitedCodes: Set<String> = []
        private var visitedAnnotations: [VisitedAnnotation] = []

        /// Small amber badge placed on countries the user has visited.
        private static let visitedMarkerImage: UIImage = {
            let size = CGSize(width: 20, height: 20)
            let amber = UIColor(red: 0.95, green: 0.61, blue: 0.24, alpha: 1.0)
            return UIGraphicsImageRenderer(size: size).image { _ in
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
                amber.setFill()
                UIBezierPath(ovalIn: rect).fill()
                let check = UIBezierPath()
                check.lineWidth = 2
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                check.move(to: CGPoint(x: size.width * 0.30, y: size.height * 0.52))
                check.addLine(to: CGPoint(x: size.width * 0.44, y: size.height * 0.67))
                check.addLine(to: CGPoint(x: size.width * 0.72, y: size.height * 0.34))
                UIColor.white.setStroke()
                check.stroke()
                UIColor.white.withAlphaComponent(0.9).setStroke()
                let ring = UIBezierPath(ovalIn: rect)
                ring.lineWidth = 1.5
                ring.stroke()
            }
        }()
        private var rendererCache: [ObjectIdentifier: MKOverlayPathRenderer] = [:]

        // MARK: Level of detail
        private var detailLevels: [[MKOverlay]] = []
        private var levelTolerances: [Double] = []
        private var currentLevel = 0
        /// Previous level kept on the map briefly after a swap, so the base imagery
        /// never flashes through while MapKit prepares the new geometry.
        private var retiringLevel: Int?
        private var retireWorkItem: DispatchWorkItem?
        private let retireDelay: TimeInterval = 0.35
        /// Use the coarsest level whose tolerance is at most this many screen points…
        private let maxToleranceInPoints = 0.5
        /// …and only fall back to a coarser level once the current one is this precise,
        /// so small zoom changes around a threshold don't cause swaps.
        private let minToleranceInPoints = 0.18

        // MARK: Selection highlight
        private var highlightOverlays: [MKOverlay] = []

        // MARK: - Dice spin state
        private var lastDiceSpinTarget: String? = nil
        private var spinTimer: Timer?
        private var spinStartTime: Date = .now
        private let spinDuration: TimeInterval = 2.5
        private var spinStartLon: Double = 0
        private var spinStartLat: Double = 20
        private var spinStartDistance: Double = 35_000_000
        private var spinEndCoordinate: CLLocationCoordinate2D = .init(latitude: 20, longitude: 20)
        private var spinEndDistance: Double = 12_000_000
        private var spinTotalLonTravel: Double = 0
        private var spinTargetCode: String = ""
        private var spinEndCameraLat: Double = 20
        private weak var spinMapView: MKMapView?

        /// Camera distance range for the end of a spin: small countries get a closer
        /// view so they are easy to spot, large ones still fit on screen.
        private let spinMinEndDistance: Double = 2_500_000
        private let spinMaxEndDistance: Double = 12_000_000
        /// Camera distance as a multiple of the country's larger dimension.
        private let spinDistancePerCountrySize: Double = 4.0

        /// How many degrees south the camera center is offset from the target country
        /// at `spinMaxEndDistance`, so the country appears above the CountryDetailCard
        /// rather than behind it. Scaled down proportionally for closer cameras.
        private let spinCameraLatOffset: Double = -18.0

        init(appState: AppState, onGeometryLoaded: @escaping () -> Void) {
            self.appState = appState
            self.onGeometryLoaded = onGeometryLoaded
        }

        func stop() {
            geometryTask?.cancel()
            spinTimer?.invalidate()
            retireWorkItem?.cancel()
        }

        // MARK: - Country geometry lookups

        private func overlays(for isoCode: String, in level: [MKOverlay]) -> [MKOverlay] {
            level.filter { ($0 as? MKShape)?.title == isoCode }
        }

        nonisolated private static func polygons(of overlay: MKOverlay) -> [MKPolygon] {
            if let multi = overlay as? MKMultiPolygon { return multi.polygons }
            if let polygon = overlay as? MKPolygon { return [polygon] }
            return []
        }

        /// The single largest sub-polygon (by bounding-box area) of a country.
        ///
        /// Unioning the bounding rects of every disjoint part would break for countries
        /// with far-flung exclaves that cross the antimeridian (e.g. the USA's westernmost
        /// Aleutian Islands near +179° while the mainland sits near -125°..-67°): the union
        /// spans almost the entire globe width and its center lands near longitude 0.
        private func mainPolygon(for isoCode: String) -> MKPolygon? {
            overlays(for: isoCode, in: detailLevels.last ?? [])
                .flatMap(Self.polygons(of:))
                .max { CountryGeometry.area(of: $0.boundingMapRect) < CountryGeometry.area(of: $1.boundingMapRect) }
        }

        /// A representative point inside the country, used for markers and camera targeting.
        func centroid(for isoCode: String) -> CLLocationCoordinate2D? {
            mainPolygon(for: isoCode).map { CountryGeometry.visualCenter(of: $0).coordinate }
        }

        /// Camera distance that frames the country comfortably.
        private func preferredCameraDistance(for isoCode: String) -> Double {
            guard let rect = mainPolygon(for: isoCode)?.boundingMapRect else { return spinMaxEndDistance }
            let latitude = MKMapPoint(x: rect.midX, y: rect.midY).coordinate.latitude
            let sizeMeters = max(rect.width, rect.height) * MKMetersPerMapPointAtLatitude(latitude)
            return min(max(sizeMeters * spinDistancePerCountrySize, spinMinEndDistance), spinMaxEndDistance)
        }

        // MARK: - Dice spin animation

        /// Called from `updateUIView` whenever `appState.diceSpinTarget` may have changed.
        func handleDiceSpinTargetIfNeeded(_ target: String?, in mapView: MKMapView) {
            guard !isLoadingGeometry else { return }
            if let target {
                guard target != lastDiceSpinTarget else { return }
                lastDiceSpinTarget = target
                if let coordinate = centroid(for: target) {
                    startSpinAnimation(to: coordinate, targetCode: target, in: mapView)
                } else {
                    // No GeoJSON data for this code — fall back to instant select.
                    appState.selectCountry(code: target)
                    refreshOverlayColors(on: mapView)
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
            spinEndDistance = preferredCameraDistance(for: targetCode)
            // Bias the camera's final latitude southward so the country appears
            // above the CountryDetailCard rather than behind it.
            let latOffset = spinCameraLatOffset * spinEndDistance / spinMaxEndDistance
            spinEndCameraLat = min(max(coordinate.latitude + latOffset, -75), 75)
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
            guard let mapView = spinMapView else { spinTimer?.invalidate(); spinTimer = nil; return }

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
            updateOverlayDetailIfNeeded(on: mapView)
            appState.selectCountry(code: spinTargetCode)
            refreshOverlayColors(on: mapView)
            appState.diceSpinTarget = nil
            lastDiceSpinTarget = nil
        }

        private var isSpinning: Bool { spinTimer != nil }

        // MARK: - Tap handling

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let mapView = recognizer.view as? MKMapView, !isSpinning else { return }
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
                refreshOverlayColors(on: mapView)
            }
        }

        private func hitTest(mapPoint: MKMapPoint, in mapView: MKMapView) -> String? {
            var bestISO: String? = nil
            var bestArea: Double = .infinity

            for overlay in detailLevels.indices.contains(currentLevel) ? detailLevels[currentLevel] : [] {
                let rect = overlay.boundingMapRect
                guard rect.contains(mapPoint) else { continue }
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
                let area = rect.size.width * rect.size.height
                if area < bestArea {
                    bestArea = area
                    bestISO = (overlay as? MKShape)?.title ?? nil
                }
            }
            return bestISO
        }

        func loadGeoJSON(into map: MKMapView) {
            geometryTask = Task { @MainActor [weak self, weak map] in
                do {
                    guard let url = Bundle.main.url(forResource: "world-countries", withExtension: "geojson")
                            ?? Bundle.main.url(forResource: "world-countries", withExtension: "geo.json") else {
                        throw CocoaError(.fileNoSuchFile)
                    }
                    let prepared = try await CountryOverlayStore.shared.load(from: url)
                    guard !Task.isCancelled, let self, let map else { return }

                    detailLevels = prepared.levels
                    levelTolerances = prepared.tolerances
                    currentLevel = desiredLevel(for: map) ?? 0
                    categoryByISO3 = Self.buildCategoryLookup(from: appState)
                    lastVisaSignature = Self.visaSignature(for: appState)
                    lastVisitSignature = nil
                    isLoadingGeometry = false

                    // Keep native place labels above the opaque country fills.
                    map.addOverlays(detailLevels[currentLevel], level: .aboveRoads)
                    refreshOverlayColors(on: map)
                    handleDiceSpinTargetIfNeeded(appState.diceSpinTarget, in: map)
                    onGeometryLoaded()
                } catch {
                    guard !Task.isCancelled, let self, let map else { return }
                    isLoadingGeometry = false
                    print("[WhereCanIGo] GeoJSON load error: \(error)")
                    handleDiceSpinTargetIfNeeded(appState.diceSpinTarget, in: map)
                    onGeometryLoaded()
                }
            }
        }

        /// Walks common property keys to find an ISO 3166-1 alpha-3 country code.
        nonisolated static func extractISO3(from propertiesData: Data?) -> String? {
            guard let data = propertiesData,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            for key in ["ISO_A3", "ISO3166-1-Alpha-3", "iso_a3", "ADM0_A3", "id", "ISO3"] {
                if let value = json[key] as? String, value.count == 3, value != "-99" {
                    return value.uppercased()
                }
            }
            switch json["name"] as? String {
            case "France": return "FRA"
            case "Norway": return "NOR"
            case "Kosovo": return "XKX"
            default: return nil
            }
        }

        func refreshOverlayColors(on map: MKMapView) {
            guard !isLoadingGeometry else { return }

            if !isSpinning { updateOverlayDetailIfNeeded(on: map) }

            let newSelected = appState.selectedCountryCode
            let selectionChanged = newSelected != lastSelectedCode

            let visaSignature = Self.visaSignature(for: appState)
            let visaChanged = visaSignature != lastVisaSignature

            let visitSignature = Self.visitSignature(for: appState)
            let visitDataChanged = visitSignature != lastVisitSignature

            guard visaChanged || visitDataChanged || selectionChanged else { return }

            var codesToRedraw = selectionChanged
                ? Set([lastSelectedCode, newSelected].compactMap { $0 })
                : Set<String>()
            if visaChanged {
                lastVisaSignature = visaSignature
                let nextCategories = Self.buildCategoryLookup(from: appState)
                codesToRedraw.formUnion(Self.changedCountryCodes(from: categoryByISO3, to: nextCategories))
                categoryByISO3 = nextCategories
            }

            if visitDataChanged {
                lastVisitSignature = visitSignature
                let newVisited = appState.visitedCountryCodes
                let visitedChanged = newVisited != visitedCodes
                visitedCodes = newVisited
                if visitedChanged { refreshVisitedAnnotations(on: map) }
            }

            if !codesToRedraw.isEmpty {
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
            if selectionChanged {
                rebuildSelectionHighlight(on: map)
            }
        }

        static func changedCountryCodes(from previous: [String: VisaCategory],
                                        to next: [String: VisaCategory]) -> Set<String> {
            Set(previous.keys).union(next.keys).filter {
                (previous[$0] ?? .visaRequired) != (next[$0] ?? .visaRequired)
            }
        }

        private func apply(renderer: MKOverlayPathRenderer, for overlay: MKOverlay) {
            let iso = (overlay as? MKShape)?.title ?? nil
            let category = iso.flatMap { categoryByISO3[$0] } ?? .visaRequired
            let isSelected = iso != nil && iso == appState.selectedCountryCode
            // The selection outline is a separate overlay drawn above every fill
            // (see `rebuildSelectionHighlight`), so all fills share the same thin border.
            renderer.fillColor = UIColor(category.color).withAlphaComponent(isSelected ? 1.0 : 0.85)
            renderer.strokeColor = UIColor.white.withAlphaComponent(0.7)
            renderer.lineWidth = 0.5
        }

        /// Rebuilds the amber "visited" badges pinned at each visited country's centroid.
        private func refreshVisitedAnnotations(on map: MKMapView) {
            if !visitedAnnotations.isEmpty {
                map.removeAnnotations(visitedAnnotations)
                visitedAnnotations.removeAll()
            }
            for code in visitedCodes {
                guard let coordinate = centroid(for: code) else { continue }
                let annotation = VisitedAnnotation()
                annotation.coordinate = coordinate
                annotation.title = code
                visitedAnnotations.append(annotation)
            }
            map.addAnnotations(visitedAnnotations)
        }

        // MARK: - Level of detail switching

        /// Coarsest level that keeps simplification error under `maxToleranceInPoints`,
        /// with hysteresis so the level only coarsens once it is clearly over-detailed.
        private func desiredLevel(for map: MKMapView) -> Int? {
            guard !levelTolerances.isEmpty, map.bounds.width > 0 else { return nil }
            let mapPointsPerPoint = map.visibleMapRect.size.width / Double(map.bounds.width)
            guard mapPointsPerPoint.isFinite, mapPointsPerPoint > 0 else { return nil }

            func coarsestLevel(maxPoints: Double) -> Int {
                levelTolerances.firstIndex { $0 <= maxPoints * mapPointsPerPoint } ?? levelTolerances.count - 1
            }
            let needed = coarsestLevel(maxPoints: maxToleranceInPoints)
            if needed > currentLevel { return needed }
            let relaxed = coarsestLevel(maxPoints: minToleranceInPoints)
            return relaxed < currentLevel ? relaxed : currentLevel
        }

        private func updateOverlayDetailIfNeeded(on map: MKMapView) {
            guard !detailLevels.isEmpty,
                  let next = desiredLevel(for: map),
                  next != currentLevel else { return }

            retireWorkItem?.cancel()
            if let retiring = retiringLevel, retiring != next {
                removeOverlays(detailLevels[retiring], from: map)
            }
            let nextAlreadyOnMap = retiringLevel == next
            let previous = currentLevel
            currentLevel = next

            // Add the new level before removing the old one so there is never a frame
            // where the country fills are missing.
            if !nextAlreadyOnMap {
                map.addOverlays(detailLevels[next], level: .aboveRoads)
            }
            rebuildSelectionHighlight(on: map)

            retiringLevel = previous
            let work = DispatchWorkItem { [weak self, weak map] in
                guard let self, let map, let retiring = self.retiringLevel else { return }
                self.removeOverlays(self.detailLevels[retiring], from: map)
                self.retiringLevel = nil
            }
            retireWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + retireDelay, execute: work)
        }

        private func removeOverlays(_ overlays: [MKOverlay], from map: MKMapView) {
            map.removeOverlays(overlays)
            for overlay in overlays {
                rendererCache.removeValue(forKey: ObjectIdentifier(overlay))
            }
        }

        // MARK: - Selection highlight

        /// Draws the selected country's outline above all fills but below native labels,
        /// using the geometry of the current detail level.
        private func rebuildSelectionHighlight(on map: MKMapView) {
            if !highlightOverlays.isEmpty {
                map.removeOverlays(highlightOverlays)
                highlightOverlays.removeAll()
            }

            guard let code = appState.selectedCountryCode,
                  detailLevels.indices.contains(currentLevel) else { return }

            let polygons = overlays(for: code, in: detailLevels[currentLevel]).flatMap(Self.polygons(of:))
            guard !polygons.isEmpty else { return }

            var rings: [MKPolyline] = []
            for polygon in polygons {
                for ring in [polygon] + (polygon.interiorPolygons ?? []) {
                    rings.append(MKPolyline(points: ring.points(), count: ring.pointCount))
                }
            }
            highlightOverlays = [SelectionGlowOverlay(rings), SelectionLineOverlay(rings)]

            map.addOverlays(highlightOverlays, level: .aboveRoads)
        }

        /// Signature of only the data that affects overlay fill color.
        static func visaSignature(for appState: AppState) -> Int {
            var hasher = Hasher()
            hasher.combine(appState.dataRevision)
            hasher.combine(appState.data.passportCode)
            hasher.combine(Calendar.current.startOfDay(for: appState.visaReferenceDate))
            for entry in appState.data.defaultVisas {
                hasher.combine(entry.countryCode)
                hasher.combine(entry.category)
            }
            for visa in appState.data.personalVisas {
                hasher.combine(visa.id)
                hasher.combine(visa.countryCode)
                hasher.combine(visa.expiryDate.timeIntervalSince1970)
                hasher.combine(visa.effectiveDate?.timeIntervalSince1970)
                hasher.combine(visa.coverage)
            }
            return hasher.finalize()
        }

        /// Signature of only the data that affects the "visited" annotations.
        static func visitSignature(for appState: AppState) -> Int {
            var hasher = Hasher()
            hasher.combine(appState.dataRevision)
            for visit in appState.data.visits {
                hasher.combine(visit.countryCode)
            }
            return hasher.finalize()
        }

        static func buildCategoryLookup(from appState: AppState) -> [String: VisaCategory] {
            let countryCodes = Set(appState.countries.map(\.code))
                .union(appState.data.defaultVisas.map(\.countryCode))
                .union(appState.data.personalVisas.map(\.countryCode))
                .union(VisaCoverage.schengenCountryCodes)
            return Dictionary(uniqueKeysWithValues: countryCodes.map {
                ($0, appState.visaCategory(for: $0))
            })
        }

        // MARK: - Ring simplification (degrees; used by WorldMapView)

        nonisolated static func simplifiedRing(_ coordinates: [CLLocationCoordinate2D], tolerance: CLLocationDegrees) -> [CLLocationCoordinate2D] {
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

        nonisolated static func coordinatesEqual(_ lhs: CLLocationCoordinate2D, _ rhs: CLLocationCoordinate2D) -> Bool {
            lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
        }

        nonisolated static func ramerDouglasPeucker(points: [CLLocationCoordinate2D], epsilon: CLLocationDegrees) -> [CLLocationCoordinate2D] {
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

        nonisolated static func perpendicularDistance(_ point: CLLocationCoordinate2D,
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

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            switch overlay {
            case let glow as SelectionGlowOverlay:
                let renderer = MKMultiPolylineRenderer(multiPolyline: glow)
                renderer.strokeColor = SelectionHighlightStyle.glowColor
                renderer.lineWidth = SelectionHighlightStyle.glowWidth
                renderer.lineJoin = .round
                renderer.lineCap = .round
                return renderer
            case let line as SelectionLineOverlay:
                let renderer = MKMultiPolylineRenderer(multiPolyline: line)
                renderer.strokeColor = SelectionHighlightStyle.lineColor
                renderer.lineWidth = SelectionHighlightStyle.lineWidth
                renderer.lineJoin = .round
                renderer.lineCap = .round
                return renderer
            case let polygon as MKPolygon:
                let renderer = MKPolygonRenderer(polygon: polygon)
                rendererCache[ObjectIdentifier(overlay)] = renderer
                apply(renderer: renderer, for: overlay)
                return renderer
            case let multiPolygon as MKMultiPolygon:
                let renderer = MKMultiPolygonRenderer(multiPolygon: multiPolygon)
                rendererCache[ObjectIdentifier(overlay)] = renderer
                apply(renderer: renderer, for: overlay)
                return renderer
            default:
                return MKOverlayRenderer(overlay: overlay)
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is VisitedAnnotation else { return nil }
            let id = "visited-badge"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.image = Self.visitedMarkerImage
            view.canShowCallout = false
            view.displayPriority = .required
            view.collisionMode = .circle
            return view
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if !isSpinning { updateOverlayDetailIfNeeded(on: mapView) }
        }
    }
}

/// Marker identifying a country the user has visited (kept distinct from other annotations).
final class VisitedAnnotation: MKPointAnnotation {}
