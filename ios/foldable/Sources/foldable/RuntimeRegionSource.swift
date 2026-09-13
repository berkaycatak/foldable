import CoreGraphics
import Foundation
import UIKit

/// Reads Apple's reserved regions through the Objective-C runtime.
///
/// Apple's Swift-facing shape is:
///
/// ```swift
/// let regions = view.reservedRegions(kind: .division, options: .includeInactive)
/// let frames = regions.map(\.frame)
/// ```
///
/// This is the safer of the two runtime sources: the call is a plain instance
/// method on `UIView` returning an array, so nothing has to be constructed and
/// no delegate has to be installed. A wrong guess returns an empty array.
final class RuntimeRegionSource: RegionSource {

  /// Candidate Objective-C spellings of `reservedRegions(kind:options:)`.
  ///
  /// UNVERIFIED: Apple's reference documentation is not published, so the
  /// exact selector is unknown. When none of these match, the real name is
  /// discovered from the runtime instead of guessed further.
  private static let selectorCandidates = [
    "reservedRegionsOfKind:options:",
    "reservedRegionsForKind:options:",
    "reservedRegionsWithKind:options:",
    "reservedRegionsOfKind:",
    "reservedRegionsForKind:",
    "reservedRegionsWithKind:",
  ]

  /// UNVERIFIED raw values, assumed to follow Apple's declaration order.
  private enum RawKind: Int {
    case division = 0
    case occlusion = 1
  }

  /// UNVERIFIED option bit for `.includeInactive`.
  private static let includeInactiveOption = 1

  /// Property names that might carry a region's active flag.
  private static let activeKeys = ["isActive", "active"]

  /// Property names that might carry a region's rectangle.
  private static let frameKeys = ["frame", "rect", "bounds"]

  private var resolvedSelector: Selector?
  private var resolvedArgumentCount = 2

  static var isAvailable: Bool {
    return resolveOnUIView() != nil
  }

  /// Finds the selector on `UIView`, first from the candidate list and then by
  /// scanning the runtime for anything named like a reserved-region accessor.
  private static func resolveOnUIView() -> Selector? {
    if let known = ObjCRuntimeSupport.firstInstanceResponding(
      UIView.self, selectorCandidates)
    {
      return known
    }

    let discovered = ObjCRuntimeSupport.discoverSelectors(
      on: UIView.self, containing: "reservedregion")
    // Prefer the richest overload, which is the one taking options.
    let sorted = discovered.sorted {
      $0.filter { $0 == ":" }.count > $1.filter { $0 == ":" }.count
    }
    guard let best = sorted.first else { return nil }
    return NSSelectorFromString(best)
  }

  func regions(in view: UIView) -> [FoldableRegion] {
    guard let selector = resolveSelector() else { return [] }

    var result: [FoldableRegion] = []
    // Folds are requested with `.includeInactive`: while the device is flat
    // the division is inactive and zero-width, so a default query omits it,
    // yet knowing where it will appear is still useful.
    result += read(
      view, selector, kind: .division,
      options: Self.includeInactiveOption, mapTo: .division)
    // Only active occlusions matter; an inactive camera cutout is not a thing.
    result += read(
      view, selector, kind: .occlusion, options: 0, mapTo: .occlusion)
    return result
  }

  private func read(
    _ view: UIView,
    _ selector: Selector,
    kind: RawKind,
    options: Int,
    mapTo mapped: FoldableRegionKind
  ) -> [FoldableRegion] {
    let args =
      resolvedArgumentCount >= 2 ? [kind.rawValue, options] : [kind.rawValue]
    guard
      let objects = ObjCRuntimeSupport.callArrayMethod(
        on: view, selector: selector, args: args)
    else { return [] }

    return objects.compactMap { region in
      var frame: CGRect?
      for key in Self.frameKeys {
        if let candidate = ObjCRuntimeSupport.rect(from: region, key: key) {
          frame = candidate
          break
        }
      }
      guard let frame = frame else { return nil }

      // When the platform does not expose an explicit flag, fall back to
      // geometry: Apple documents the fold division as inactive and
      // zero-width while the device is flat.
      let isActive =
        ObjCRuntimeSupport.bool(from: region, keys: Self.activeKeys)
        ?? (frame.width > 0 && frame.height > 0)

      return FoldableRegion(kind: mapped, frame: frame, isActive: isActive)
    }
  }

  private func resolveSelector() -> Selector? {
    if let cached = resolvedSelector { return cached }
    guard let selector = Self.resolveOnUIView() else { return nil }
    resolvedSelector = selector
    resolvedArgumentCount = ObjCRuntimeSupport.argumentCount(of: selector)
    return selector
  }
}
