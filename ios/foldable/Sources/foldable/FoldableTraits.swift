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
}
