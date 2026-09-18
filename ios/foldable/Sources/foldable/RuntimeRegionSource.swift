import CoreGraphics
import Foundation
import UIKit

/// Reads Apple's reserved regions through the Objective-C runtime.
///
/// The real API, confirmed against the iOS 27.1 SDK headers:
///
/// ```objc
/// @interface UIView (ReservedRegion)
/// - (NSArray<UIViewReservedRegion *> *)reservedRegionsOfKind:(UIViewReservedRegionKind *)kind
///                                                    options:(UIViewReservedRegionQueryOptions)options;
/// @end
///
/// @interface UIViewReservedRegionKind : NSObject
/// + (instancetype)occlusionRegionKind;
/// + (instancetype)divisionRegionKind;    // the kind is an OBJECT, not an enum
/// @end
///
/// @interface UIViewReservedRegion : NSObject
/// @property (readonly) CGRect frame;
/// @property (readonly) UIEdgeInsets margins;
/// @property (readonly, getter=isActive) BOOL active;
/// @end
///
/// UIViewReservedRegionQueryOptionsNone = 0, ...IncludeInactive = 1 << 0
/// ```
///
/// Safer than the hinge side: a plain instance method returning an array, so
/// nothing has to be constructed and no callback has to be installed.
final class RuntimeRegionSource: RegionSource {

  private static let selectorName = "reservedRegionsOfKind:options:"
  private static let includeInactive: UInt = 1 << 0

  private var resolvedSelector: Selector?
  private var divisionKind: NSObject?
  private var occlusionKind: NSObject?

  static var isAvailable: Bool {
    return UIView.instancesRespond(to: NSSelectorFromString(selectorName))
      && NSClassFromString("UIViewReservedRegionKind") != nil
  }

  func regions(in view: UIView) -> [FoldableRegion] {
    guard let selector = resolveSelector() else { return [] }

    var result: [FoldableRegion] = []
    // The fold is inactive and zero width while the device is flat, so it is
    // requested with includeInactive: knowing where it will appear is useful
    // even before it does. Inactive regions are reported, never dropped.
    if let kind = divisionKindObject() {
      result += read(
        view, selector, kind: kind, options: Self.includeInactive,
        mapTo: .division)
    }
    // An occlusion is only active while that camera is in use, so an inactive
    // one carries no information.
    if let kind = occlusionKindObject() {
      result += read(view, selector, kind: kind, options: 0, mapTo: .occlusion)
    }
    return result
  }

  private func read(
    _ view: UIView, _ selector: Selector, kind: NSObject, options: UInt,
    mapTo mapped: FoldableRegionKind
  ) -> [FoldableRegion] {
    guard
      let regions = ObjCRuntimeSupport.callArrayMethod(
        on: view, selector: selector, object: kind, options: options)
    else { return [] }

    return regions.compactMap { region in
      guard let frame = ObjCRuntimeSupport.rect(from: region, key: "frame")
      else { return nil }
      let isActive =
        ObjCRuntimeSupport.bool(from: region, keys: ["isActive", "active"])
        ?? (frame.width > 0 && frame.height > 0)
      return FoldableRegion(kind: mapped, frame: frame, isActive: isActive)
    }
  }

  private func resolveSelector() -> Selector? {
    if let cached = resolvedSelector { return cached }
    let selector = NSSelectorFromString(Self.selectorName)
    guard UIView.instancesRespond(to: selector) else { return nil }
    resolvedSelector = selector
    return selector
  }

  private func divisionKindObject() -> NSObject? {
    if divisionKind == nil {
      divisionKind = ObjCRuntimeSupport.classObject(
        "UIViewReservedRegionKind", "divisionRegionKind")
    }
    return divisionKind
  }

  private func occlusionKindObject() -> NSObject? {
    if occlusionKind == nil {
      occlusionKind = ObjCRuntimeSupport.classObject(
        "UIViewReservedRegionKind", "occlusionRegionKind")
    }
    return occlusionKind
  }
}
