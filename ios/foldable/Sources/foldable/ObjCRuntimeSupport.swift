import CoreGraphics
import Foundation
import ObjectiveC
import UIKit

/// Objective-C runtime helpers used to reach APIs that are not in the SDK this
/// package is compiled against.
///
/// The iPhone Duo hinge APIs ship in the iOS 27.1 SDK, but this package must
/// keep compiling with older toolchains and keep running on iOS 13. No iOS 27
/// type is ever named in Swift source here, only looked up as a string at
/// runtime, so the compiler never sees an unknown symbol and the deployment
/// target stays at 13.0.
///
/// Every lookup is guarded: a wrong guess yields `nil` and the feature turns
/// itself off. Nothing here may crash on a device where the API is absent, or
/// shaped differently than expected.
enum ObjCRuntimeSupport {

  // MARK: - Selector discovery

  /// Returns the first selector in `names` the object actually responds to.
  static func firstResponding(_ object: NSObject, _ names: [String]) -> Selector? {
    for name in names {
      let selector = NSSelectorFromString(name)
      if object.responds(to: selector) { return selector }
    }
    return nil
  }

  /// Returns the first selector in `names` instances of `cls` respond to.
  static func firstInstanceResponding(_ cls: AnyClass, _ names: [String]) -> Selector? {
    for name in names {
      let selector = NSSelectorFromString(name)
      if cls.instancesRespond(to: selector) { return selector }
    }
    return nil
  }

  /// Every instance selector on `cls` whose name contains `substring`.
  ///
  /// This is how the package avoids guessing Objective-C selector spellings:
  /// when the candidate list misses, the real name is discovered instead.
  static func discoverSelectors(
    on cls: AnyClass, containing substring: String
  ) -> [String] {
    var count: UInt32 = 0
    guard let list = class_copyMethodList(cls, &count) else { return [] }
    defer { free(list) }

    let needle = substring.lowercased()
    var found: [String] = []
    for index in 0..<Int(count) {
      let name = NSStringFromSelector(method_getName(list[index]))
      if name.lowercased().contains(needle) { found.append(name) }
    }
    return found
  }

  /// Every property name declared on `cls`.
  static func propertyNames(of cls: AnyClass) -> [String] {
    var count: UInt32 = 0
    guard let list = class_copyPropertyList(cls, &count) else { return [] }
    defer { free(list) }

    var names: [String] = []
    for index in 0..<Int(count) {
      names.append(String(cString: property_getName(list[index])))
    }
    return names
  }

  /// Whether `cls` conforms to the Objective-C protocol named `name`.
  ///
  /// Used before handing an object to an API that requires conformance.
  /// `UIView.addInteraction` will crash on a non-conforming object.
  static func conforms(_ cls: AnyClass, toProtocolNamed name: String) -> Bool {
    guard let proto = objc_getProtocol(name) else { return false }
    return class_conformsToProtocol(cls, proto)
  }

  // MARK: - Safe value access

  /// Whether `object` exposes `key` as a declared property.
  ///
  /// `value(forKey:)` raises `NSUnknownKeyException` for an unknown key, and
  /// Swift cannot catch Objective-C exceptions, so every KVC read in this
  /// package is gated on this check.
  static func hasProperty(_ object: NSObject, _ key: String) -> Bool {
    let cls: AnyClass = type(of: object)
    if class_getProperty(cls, key) != nil { return true }
    return object.responds(to: NSSelectorFromString(key))
  }

  /// Reads a key path safely, returning `nil` when any segment is missing.
  static func value(from object: NSObject, keyPath: String) -> Any? {
    var current: NSObject = object
    let segments = keyPath.split(separator: ".").map(String.init)

    for (index, segment) in segments.enumerated() {
      guard hasProperty(current, segment) else { return nil }
      guard let next = current.value(forKey: segment) else { return nil }
      if index == segments.count - 1 { return next }
      guard let nextObject = next as? NSObject else { return nil }
      current = nextObject
    }
    return nil
  }

  /// Reads the first key path that yields a number.
  static func number(from object: NSObject, keyPaths: [String]) -> Double? {
    for keyPath in keyPaths {
      guard let raw = value(from: object, keyPath: keyPath) else { continue }
      if let number = raw as? NSNumber { return number.doubleValue }
      // A wrapper such as NSMeasurement exposes its magnitude one level down.
      if let wrapper = raw as? NSObject,
        let inner = value(from: wrapper, keyPath: "doubleValue") as? NSNumber
      {
        return inner.doubleValue
      }
    }
    return nil
  }

  /// Reads a `CGRect` property.
  ///
  /// Goes through KVC, which boxes the struct into an `NSValue`, avoiding the
  /// `objc_msgSend_stret` ABI differences between architectures.
  static func rect(from object: NSObject, key: String) -> CGRect? {
    guard hasProperty(object, key) else { return nil }
    guard let boxed = object.value(forKey: key) as? NSValue else { return nil }
    return boxed.cgRectValue
  }

  /// Reads a boolean property, or `nil` when it is absent.
  static func bool(from object: NSObject, keys: [String]) -> Bool? {
    for key in keys {
      guard hasProperty(object, key) else { continue }
      if let number = object.value(forKey: key) as? NSNumber {
        return number.boolValue
      }
    }
    return nil
  }

  // MARK: - Calling methods with non-object arguments

  private typealias OneIntArrayIMP =
    @convention(c) (AnyObject, Selector, Int) -> NSArray?
  private typealias TwoIntArrayIMP =
    @convention(c) (AnyObject, Selector, Int, Int) -> NSArray?

  /// Invokes a method taking one or two integer arguments and returning an
  /// array.
  ///
  /// `perform(_:with:)` only passes objects and `NSInvocation` is unavailable
  /// in Swift, so the implementation pointer is cast to a C function instead.
  static func callArrayMethod(
    on object: NSObject, selector: Selector, args: [Int]
  ) -> [NSObject]? {
    guard object.responds(to: selector) else { return nil }
    guard let imp = class_getMethodImplementation(type(of: object), selector)
    else { return nil }

    switch args.count {
    case 1:
      let function = unsafeBitCast(imp, to: OneIntArrayIMP.self)
      return function(object, selector, args[0]) as? [NSObject]
    case 2:
      let function = unsafeBitCast(imp, to: TwoIntArrayIMP.self)
      return function(object, selector, args[0], args[1]) as? [NSObject]
    default:
      return nil
    }
  }

  /// The number of arguments a selector takes, from its colon count.
  static func argumentCount(of selector: Selector) -> Int {
    return NSStringFromSelector(selector).filter { $0 == ":" }.count
  }
}
