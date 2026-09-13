import Foundation
import ObjectiveC
import UIKit

/// Dumps the Objective-C runtime shape of the hinge APIs.
///
/// Apple has not published reference documentation for `UIHingeInteraction`,
/// so this package resolves it through the runtime against candidate names.
/// This dump is how those guesses get replaced with facts: run it on real
/// hardware and the real selectors, properties and protocols come back.
enum FoldableDiagnostics {

  private static let classesOfInterest = [
    "UIHingeInteraction",
    "UIHingeInteractionDelegate",
    "UIHinge",
    "UIHingeState",
    "UIViewReservedRegion",
    "UIReservedRegion",
  ]

  /// Everything known about the hinge APIs on this device.
  static func dump() -> [String: Any] {
    var out: [String: Any] = [:]
    out["systemVersion"] = UIDevice.current.systemVersion
    out["model"] = UIDevice.current.model
    out["hingeApiPresent"] = FoldableSourceFactory.hingeApiPresent
    out["regionApiPresent"] = FoldableSourceFactory.regionApiPresent

    #if FOLDABLE_NATIVE_API
      out["builtWithNativeApi"] = true
    #else
      out["builtWithNativeApi"] = false
    #endif

    var classes: [String: Any] = [:]
    for name in classesOfInterest {
      guard let cls = NSClassFromString(name) else {
        classes[name] = NSNull()
        continue
      }
      classes[name] = [
        "superclass": String(describing: class_getSuperclass(cls)),
        "instanceMethods": methodNames(of: cls, classMethods: false),
        "classMethods": methodNames(of: cls, classMethods: true),
        "properties": ObjCRuntimeSupport.propertyNames(of: cls),
        "protocols": protocolNames(of: cls),
      ]
    }
    out["classes"] = classes

    // The selector spelling of reservedRegions(kind:options:) is the single
    // most valuable unknown, so UIView is scanned directly.
    out["uiviewReservedSelectors"] = ObjCRuntimeSupport.discoverSelectors(
      on: UIView.self, containing: "reserved")
    out["uiviewHingeSelectors"] = ObjCRuntimeSupport.discoverSelectors(
      on: UIView.self, containing: "hinge")
    out["uidevicehingeSelectors"] = ObjCRuntimeSupport.discoverSelectors(
      on: UIDevice.self, containing: "hinge")

    if let proto = objc_getProtocol("UIHingeInteractionDelegate") {
      out["delegateMethods"] = protocolMethodNames(of: proto)
    } else {
      out["delegateMethods"] = NSNull()
    }

    return out
  }

  private static func methodNames(of cls: AnyClass, classMethods: Bool) -> [String] {
    guard let target: AnyClass = classMethods ? object_getClass(cls) : cls
    else { return [] }
    var count: UInt32 = 0
    guard let list = class_copyMethodList(target, &count) else { return [] }
    defer { free(list) }
    return (0..<Int(count)).map {
      NSStringFromSelector(method_getName(list[$0]))
    }
  }

  private static func protocolNames(of cls: AnyClass) -> [String] {
    var count: UInt32 = 0
    guard let list = class_copyProtocolList(cls, &count) else { return [] }
    return (0..<Int(count)).map { String(cString: protocol_getName(list[$0])) }
  }

  private static func protocolMethodNames(of proto: Protocol) -> [String] {
    var names: [String] = []
    for isRequired in [true, false] {
      var count: UInt32 = 0
      guard
        let descriptions = protocol_copyMethodDescriptionList(
          proto, isRequired, true, &count)
      else { continue }
      defer { free(descriptions) }
      for index in 0..<Int(count) {
        guard let selector = descriptions[index].name else { continue }
        let types = descriptions[index].types.map { String(cString: $0) } ?? ""
        names.append("\(NSStringFromSelector(selector))  \(types)")
      }
    }
    return names
  }
}
