import MapKit
import UIKit

// MARK: - Selection outline

/// Soft halo drawn under the selection outline. Added above every country fill so
/// the whole stroke stays above neighbouring countries.
final class SelectionGlowOverlay: MKMultiPolyline {}

/// Crisp outline of the selected country.
final class SelectionLineOverlay: MKMultiPolyline {}

enum SelectionHighlightStyle {
    static let lineColor = UIColor.white
    static let lineWidth: CGFloat = 2.5
    static let glowColor = UIColor.white.withAlphaComponent(0.32)
    static let glowWidth: CGFloat = 9
}
