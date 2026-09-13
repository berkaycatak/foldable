#if FOLDABLE_NATIVE_API

  import UIKit

  // This file is excluded from the build unless FOLDABLE_NATIVE_API is
  // defined, which requires an SDK that actually declares the hinge APIs
  // (iOS 27.1 / Xcode 27.1). Until then the runtime sources carry the feature,
  // and the package keeps compiling against iOS 13.
  //
  // To enable:
  //   * Package.swift  - uncomment .define("FOLDABLE_NATIVE_API")
  //   * foldable.podspec - uncomment the OTHER_SWIFT_FLAGS line
  //
  // The signatures below follow Apple's Tech Talks (111463, 111464) and must
  // be reconciled with the real headers before the flag is turned on. Run
  // `Foldable.debugDumpNativeApi()` on a device to confirm them.

  /// Hinge readings from the real `UIHingeInteraction`.
  @available(iOS 27.1, *)
  final class NativeHingeSource: NSObject, HingeSource {
    static var isAvailable: Bool {
      if #available(iOS 27.1, *) { return true }
      return false
    }

    var hasHinge: Bool {
      // TODO(xcode27): interaction.hinge != nil
      return false
    }

    var strategy: String { return "native" }
    var currentReading: HingeReading? { return nil }

    func start(on view: UIView, onChange: @escaping (HingeReading) -> Void) -> Bool {
      // TODO(xcode27): install UIHingeInteraction and forward
      // hinge.status / hinge.angle through onChange.
      return false
    }

    func stop() {}
  }

  /// Reserved regions from the real `view.reservedRegions(kind:options:)`.
  @available(iOS 27.1, *)
  final class NativeRegionSource: RegionSource {
    static var isAvailable: Bool {
      if #available(iOS 27.1, *) { return true }
      return false
    }

    func regions(in view: UIView) -> [FoldableRegion] {
      // TODO(xcode27):
      //   view.reservedRegions(kind: .division, options: .includeInactive)
      //   view.reservedRegions(kind: .occlusion)
      return []
    }
  }

#endif
