import UIKit

/// Chooses which hinge and region implementation to use.
///
/// The single place that knows about the compile-time split, so switching to
/// the real iOS 27.1 types later touches nothing else.
enum FoldableSourceFactory {

  /// Builds a hinge source, preferring real SDK types when available.
  static func makeHingeSource() -> HingeSource {
    #if FOLDABLE_NATIVE_API
      if NativeHingeSource.isAvailable { return NativeHingeSource() }
    #endif
    if RuntimeHingeSource.isAvailable { return RuntimeHingeSource() }
    return UnsupportedHingeSource()
  }

  /// Builds a region source, preferring real SDK types when available.
  static func makeRegionSource() -> RegionSource {
    #if FOLDABLE_NATIVE_API
      if NativeRegionSource.isAvailable { return NativeRegionSource() }
    #endif
    if RuntimeRegionSource.isAvailable { return RuntimeRegionSource() }
    return UnsupportedRegionSource()
  }

  /// Whether the hinge API symbols exist in this process.
  static var hingeApiPresent: Bool {
    #if FOLDABLE_NATIVE_API
      if NativeHingeSource.isAvailable { return true }
    #endif
    return RuntimeHingeSource.isAvailable
  }

  /// Whether the reserved-region API exists in this process.
  static var regionApiPresent: Bool {
    #if FOLDABLE_NATIVE_API
      if NativeRegionSource.isAvailable { return true }
    #endif
    return RuntimeRegionSource.isAvailable
  }
}
