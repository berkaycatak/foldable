import CoreGraphics
import UIKit

/// Fold posture, mirroring Apple's `.closed` / `.partiallyOpen` / `.fullyOpen`.
///
/// The raw values are the wire names shared with the Dart side.
enum FoldableHingeStatus: String {
  case closed
  case partiallyOpen
  case fullyOpen
  case unknown
}

/// A single hinge reading.
struct HingeReading {
  /// The coarse posture.
  let status: FoldableHingeStatus

  /// The hinge angle in **degrees**: 0 closed, 180 flat.
  ///
  /// Whatever unit the platform reports, it is normalised here so the Dart
  /// side never has to guess.
  let angleDegrees: Double?

  /// Whether the unit conversion has been confirmed against real hardware.
  let angleUnitVerified: Bool

  static let none = HingeReading(
    status: .unknown, angleDegrees: nil, angleUnitVerified: false)
}

/// The kind of a reserved region, mirroring Apple's `.division` / `.occlusion`.
enum FoldableRegionKind: String {
  case division
  case occlusion
  case unknown
}

/// A hardware-reserved area of the display, in points.
struct FoldableRegion {
  let kind: FoldableRegionKind
  let frame: CGRect
  let isActive: Bool

  /// Encodes for the platform channel. Points map 1:1 to Flutter logical
  /// pixels on iOS, so no scaling is applied.
  func toMap() -> [String: Any] {
    return [
      "kind": kind.rawValue,
      "active": isActive,
      "left": Double(frame.origin.x),
      "top": Double(frame.origin.y),
      "width": Double(frame.size.width),
      "height": Double(frame.size.height),
    ]
  }
}

/// Supplies hinge readings.
protocol HingeSource: AnyObject {
  /// Whether the hinge API symbols exist in this process.
  static var isAvailable: Bool { get }

  /// Whether this device has a hinge, or `nil` while that is still unknown.
  ///
  /// The platform only answers this through an update: `update.hinge` is nil on
  /// a device without one. So there is nothing to read until the interaction
  /// has been installed and has reported once, and callers must treat `nil` as
  /// "not yet", not as "no".
  var hasHinge: Bool? { get }

  /// Which resolution path produced the readings, reported for diagnostics.
  var strategy: String { get }

  /// The latest reading, if any.
  var currentReading: HingeReading? { get }

  /// Begins observing. Returns `false` when no reading path could be
  /// established; the caller then closes the Dart stream cleanly.
  @discardableResult
  func start(on view: UIView, onChange: @escaping (HingeReading) -> Void) -> Bool

  /// Stops observing and releases everything it attached.
  func stop()
}

/// Supplies reserved-region geometry.
protocol RegionSource: AnyObject {
  /// Whether the reserved-region API exists in this process.
  static var isAvailable: Bool { get }

  /// The regions currently reserved within `view`.
  func regions(in view: UIView) -> [FoldableRegion]
}

/// The source used on every device without hinge APIs, which today is every
/// device, and after the iPhone Duo ships will still be most of them.
final class UnsupportedHingeSource: HingeSource {
  static var isAvailable: Bool { return true }

  var hasHinge: Bool? { return false }
  var strategy: String { return "none" }
  var currentReading: HingeReading? { return nil }

  func start(on view: UIView, onChange: @escaping (HingeReading) -> Void) -> Bool {
    return false
  }

  func stop() {}
}

/// The region source used when the reserved-region API is absent.
final class UnsupportedRegionSource: RegionSource {
  static var isAvailable: Bool { return true }
  func regions(in view: UIView) -> [FoldableRegion] { return [] }
}
