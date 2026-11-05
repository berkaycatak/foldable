import UIKit

/// iOS size classes, the signal the system itself lays out from.
///
/// On iPhone Duo the cover display is compact width and the inner display is
/// regular width. Reading this beats guessing from a width breakpoint, because
/// it also accounts for Split View, where the app occupies half the screen and
/// the class changes without the device folding.
enum FoldableSizeClass: String {
  case compact
  case regular
  case unspecified

  init(_ sizeClass: UIUserInterfaceSizeClass) {
    switch sizeClass {
    case .compact: self = .compact
    case .regular: self = .regular
    default: self = .unspecified
    }
  }
}

/// Reads size classes from a view's trait collection.
enum FoldableTraits {
  /// The horizontal and vertical size classes for `view`.
  ///
  /// Returns `.unspecified` for both when there is no view to read, so callers
  /// never have to special-case a missing host.
  static func sizeClasses(for view: UIView?) -> (
    horizontal: FoldableSizeClass, vertical: FoldableSizeClass
  ) {
    guard let view = view else { return (.unspecified, .unspecified) }
    let traits = view.traitCollection
    return (
      FoldableSizeClass(traits.horizontalSizeClass),
      FoldableSizeClass(traits.verticalSizeClass)
    )
  }

  /// The physical side where the system places its vertical bar for `view`,
  /// from `UITraitCollection.verticalBarEdge` (iOS 27.1).
  ///
  /// UIKit reports the edge as leading or trailing; it is resolved against the
  /// view's layout direction here, so Dart receives the hardware side the bar
  /// is aligned to. Returns `.unknown` when there is no view to read or the
  /// trait does not exist in this process.
  static func verticalBarEdge(for view: UIView?) -> FoldableVerticalBarEdge {
    guard let view = view else { return .unknown }
    guard let raw = rawVerticalBarEdge(of: view.traitCollection) else {
      return .unknown
    }
    let rtl = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
    switch raw {
    case 1: return rtl ? .right : .left
    case 2: return rtl ? .left : .right
    default: return .none
    }
  }

  /// `UIVerticalBarEdge` as its raw value: 0 unspecified, 1 leading,
  /// 2 trailing. `nil` when the trait is absent.
  private static func rawVerticalBarEdge(of traits: UITraitCollection) -> Int? {
    #if FOLDABLE_NATIVE_API
      if #available(iOS 27.1, *) { return traits.verticalBarEdge.rawValue }
    #endif
    // Gated on the property existing: KVC on an unknown key raises an
    // Objective-C exception Swift cannot catch.
    guard ObjCRuntimeSupport.hasProperty(traits, "verticalBarEdge") else {
      return nil
    }
    return (traits.value(forKey: "verticalBarEdge") as? NSNumber)?.intValue
  }
}

/// Where the system places its vertical bar, as a physical side.
///
/// The raw values are the wire names shared with the Dart side.
enum FoldableVerticalBarEdge: String {
  case none
  case left
  case right
  case unknown
}
