import Foundation
import ObjectiveC
import QuartzCore
import UIKit

/// Reads the hinge through the Objective-C runtime.
///
/// Apple's Swift-facing shape, from Tech Talk 111464:
///
/// ```swift
/// .onHingeChange { _, context in
///     if let hinge = context.hinge, hinge.status == .partiallyOpen {
///         use(hinge.angle)
///     }
/// }
/// ```
///
/// and in UIKit, a `UIHingeInteraction` added to a view. The reference
/// documentation for that class is not published, so its initialiser and
/// delegate signatures are unknown. Rather than bet on one shape, this tries
/// several in order and reports which one worked through `strategy`, so a
/// problem in the field is diagnosable without the device in hand.
///
/// Nothing here names an iOS 27 type in Swift source, so the package still
/// compiles against older SDKs and still targets iOS 13.
final class RuntimeHingeSource: NSObject, HingeSource {

  /// How the reading was obtained.
  enum Strategy: String {
    case interactionHandler
    case interactionDelegate
    case interactionKVO
    case interactionPolling
    case notification
    case none
  }

  private static let interactionClassName = "UIHingeInteraction"

  /// Key paths that might carry the hinge object itself.
  private static let hingeKeyPaths = ["hinge", "currentHinge", "hingeState"]

  /// Key paths that might carry the angle, in preference order.
  ///
  /// Apple's `Angle` carries both units; UIKit may instead expose a plain
  /// number or a measurement. Degrees are tried first so no conversion is
  /// needed in the common case.
  private static let angleKeyPaths = [
    "angle.degrees", "angleInDegrees", "degrees",
    "angle.radians", "angleInRadians", "radians", "angle",
  ]

  /// Key paths that might carry the coarse status.
  private static let statusKeyPaths = ["status", "hingeStatus", "state"]

  /// Notification names that might announce hinge changes.
  private static let notificationNames = [
    "UIHingeInteractionDidChangeNotification",
    "UIDeviceHingeDidChangeNotification",
    "UIHingeStatusDidChangeNotification",
  ]

  private var interaction: NSObject?
  private var displayLink: CADisplayLink?
  private var observedKeyPaths: [String] = []
  private var notificationTokens: [NSObjectProtocol] = []
  private var onChange: ((HingeReading) -> Void)?
  private var latest: HingeReading?
  private var resolvedStrategy: Strategy = .none

  // MARK: - HingeSource

  static var isAvailable: Bool {
    return NSClassFromString(interactionClassName) != nil
  }

  var strategy: String { return resolvedStrategy.rawValue }

  var currentReading: HingeReading? { return latest }

  /// Whether this device actually has a hinge.
  ///
  /// Apple signals a hinge-less device with a nil hinge, so the presence of a
  /// readable hinge object is the test. The class existing is not enough,
  /// since it is linked into every device running the OS.
  var hasHinge: Bool {
    if interaction == nil { interaction = makeInteraction() }
    guard let interaction = interaction else { return false }
    return hingeObject(from: interaction) != nil
  }

  @discardableResult
  func start(on view: UIView, onChange: @escaping (HingeReading) -> Void) -> Bool {
    self.onChange = onChange

    guard let interaction = interaction ?? makeInteraction() else {
      // Last resort: the device may announce changes without the interaction.
      if attachNotifications() {
        resolvedStrategy = .notification
        return true
      }
      resolvedStrategy = .none
      return false
    }
    self.interaction = interaction

    attachToView(interaction, view: view)

    if attachHandler(interaction) {
      resolvedStrategy = .interactionHandler
    } else if attachDelegate(interaction) {
      resolvedStrategy = .interactionDelegate
    } else if attachKVO(interaction) {
      resolvedStrategy = .interactionKVO
    } else if attachPolling() {
      resolvedStrategy = .interactionPolling
    } else if attachNotifications() {
      resolvedStrategy = .notification
    } else {
      resolvedStrategy = .none
      return false
    }

    emitCurrent()
    return true
  }

  func stop() {
    displayLink?.invalidate()
    displayLink = nil
    if let interaction = interaction {
      for keyPath in observedKeyPaths {
        interaction.removeObserver(self, forKeyPath: keyPath)
      }
    }
    observedKeyPaths.removeAll()
    for token in notificationTokens {
      NotificationCenter.default.removeObserver(token)
    }
    notificationTokens.removeAll()
    if let interaction = interaction, let view = attachedView {
      removeFromView(interaction, view: view)
    }
    attachedView = nil
    interaction = nil
    onChange = nil
    resolvedStrategy = .none
  }

  // MARK: - Building the interaction

  private var attachedView: UIView?

  private func makeInteraction() -> NSObject? {
    guard let cls = NSClassFromString(Self.interactionClassName) as? NSObject.Type
    else { return nil }
    // A plain `init` is the shape every other UIKit interaction supports.
    return cls.init()
  }

  /// Installs the interaction on the view, if it is really a `UIInteraction`.
  ///
  /// `addInteraction` will crash on an object that does not conform, and
  /// conformance cannot be checked at compile time here, so it is checked at
  /// runtime instead.
  private func attachToView(_ interaction: NSObject, view: UIView) {
    guard
      ObjCRuntimeSupport.conforms(
        type(of: interaction), toProtocolNamed: "UIInteraction")
    else { return }
    view.addInteraction(unsafeBitCast(interaction, to: UIInteraction.self))
    attachedView = view
  }

  private func removeFromView(_ interaction: NSObject, view: UIView) {
    guard
      ObjCRuntimeSupport.conforms(
        type(of: interaction), toProtocolNamed: "UIInteraction")
    else { return }
    view.removeInteraction(unsafeBitCast(interaction, to: UIInteraction.self))
  }

  // MARK: - Strategy 1: a change handler block

  private func attachHandler(_ interaction: NSObject) -> Bool {
    let setters = ["setHingeChangeHandler:", "setChangeHandler:", "setHandler:"]
    guard let selector = ObjCRuntimeSupport.firstResponding(interaction, setters)
    else { return false }

    // The block ignores every argument it is passed and re-reads the value
    // from the interaction instead. Extra arguments are harmless under the C
    // calling convention, which keeps this safe against an unknown signature.
    let handler: @convention(block) () -> Void = { [weak self] in
      self?.emitCurrent()
    }
    interaction.perform(selector, with: handler)
    return true
  }

  // MARK: - Strategy 2: a delegate

  private func attachDelegate(_ interaction: NSObject) -> Bool {
    guard interaction.responds(to: NSSelectorFromString("setDelegate:"))
    else { return false }
    guard let proxy = DelegateProxy.make(notifying: { [weak self] in
      self?.emitCurrent()
    }) else { return false }

    delegateProxy = proxy
    interaction.setValue(proxy, forKey: "delegate")
    return true
  }

  private var delegateProxy: NSObject?

  // MARK: - Strategy 3: key-value observing

  private func attachKVO(_ interaction: NSObject) -> Bool {
    // Swift's key-path `observe` cannot take a runtime string, so this uses
    // the classic Objective-C observer API.
    for keyPath in Self.hingeKeyPaths {
      guard ObjCRuntimeSupport.hasProperty(interaction, keyPath) else { continue }
      interaction.addObserver(
        self, forKeyPath: keyPath, options: [.new], context: nil)
      observedKeyPaths.append(keyPath)
      return true
    }
    return false
  }

  override func observeValue(
    forKeyPath keyPath: String?,
    of object: Any?,
    change: [NSKeyValueChangeKey: Any]?,
    context: UnsafeMutableRawPointer?
  ) {
    emitCurrent()
  }

  // MARK: - Strategy 4: polling

  /// Samples the hinge once per frame while a listener is attached.
  ///
  /// The least elegant path and the most dependable one: it needs only a
  /// readable property, no callback shape at all. It runs only while the Dart
  /// stream has a subscriber.
  private func attachPolling() -> Bool {
    guard let interaction = interaction,
      hingeObject(from: interaction) != nil
    else { return false }

    let link = CADisplayLink(target: self, selector: #selector(pollTick))
    link.add(to: .main, forMode: .common)
    displayLink = link
    return true
  }

  @objc private func pollTick() {
    emitCurrent(onlyIfChanged: true)
  }

  // MARK: - Strategy 5: notifications

  private func attachNotifications() -> Bool {
    var attached = false
    for name in Self.notificationNames {
      let token = NotificationCenter.default.addObserver(
        forName: Notification.Name(name), object: nil, queue: .main
      ) { [weak self] _ in
        self?.emitCurrent()
      }
      notificationTokens.append(token)
      attached = true
    }
    return attached
  }

  // MARK: - Reading

  private func hingeObject(from interaction: NSObject) -> NSObject? {
    for keyPath in Self.hingeKeyPaths {
      if let value = ObjCRuntimeSupport.value(from: interaction, keyPath: keyPath),
        let object = value as? NSObject, !(value is NSNull)
      {
        return object
      }
    }
    return nil
  }

  private func emitCurrent(onlyIfChanged: Bool = false) {
    guard let reading = read() else { return }
    if onlyIfChanged, let previous = latest,
      previous.status == reading.status,
      Self.nearlyEqual(previous.angleDegrees, reading.angleDegrees)
    {
      return
    }
    latest = reading
    onChange?(reading)
  }

  private static func nearlyEqual(_ a: Double?, _ b: Double?) -> Bool {
    guard let a = a, let b = b else { return a == nil && b == nil }
    return abs(a - b) < 0.1
  }

  private func read() -> HingeReading? {
    guard let interaction = interaction else { return nil }
    guard let hinge = hingeObject(from: interaction) else {
      return HingeReading.none
    }

    return HingeReading(
      status: readStatus(from: hinge),
      angleDegrees: readAngle(from: hinge),
      // Flipped to true once the unit and zero point are confirmed on real
      // hardware; see FoldableDiagnostics.
      angleUnitVerified: false
    )
  }

  private func readStatus(from hinge: NSObject) -> FoldableHingeStatus {
    for keyPath in Self.statusKeyPaths {
      guard let raw = ObjCRuntimeSupport.value(from: hinge, keyPath: keyPath)
      else { continue }

      if let text = raw as? String {
        return FoldableHingeStatus(rawValue: text) ?? .unknown
      }
      if let number = raw as? NSNumber {
        // UNVERIFIED raw values, assumed to follow Apple's declaration order
        // of closed, partiallyOpen, fullyOpen.
        switch number.intValue {
        case 0: return .closed
        case 1: return .partiallyOpen
        case 2: return .fullyOpen
        default: return .unknown
        }
      }
    }

    // Fall back to deriving posture from the angle.
    guard let degrees = readAngle(from: hinge) else { return .unknown }
    if degrees <= 5 { return .closed }
    if degrees >= 175 { return .fullyOpen }
    return .partiallyOpen
  }

  /// Reads the angle and normalises it to degrees.
  ///
  /// UNVERIFIED: Apple documents neither the unit nor the zero point of
  /// `hinge.angle`. A magnitude within a full turn in radians is treated as
  /// radians; anything larger is already degrees. Both assumptions are
  /// reported to Dart through `angleUnitVerified: false`.
  private func readAngle(from hinge: NSObject) -> Double? {
    for keyPath in Self.angleKeyPaths {
      guard
        let value = ObjCRuntimeSupport.number(from: hinge, keyPaths: [keyPath])
      else { continue }

      if keyPath.hasSuffix("degrees") || keyPath.hasSuffix("Degrees") {
        return normalise(value)
      }
      if keyPath.hasSuffix("radians") || keyPath.hasSuffix("Radians") {
        return normalise(value * 180.0 / Double.pi)
      }
      // Unlabelled: infer from magnitude. A hinge never opens past 180
      // degrees, so a value at or below 2*pi must be radians.
      let degrees = abs(value) <= (2 * Double.pi) ? value * 180.0 / .pi : value
      return normalise(degrees)
    }
    return nil
  }

  /// Clamps to the physically meaningful range.
  ///
  /// If the device turns out to report 0 for flat rather than closed, this is
  /// the single line that has to change.
  private func normalise(_ degrees: Double) -> Double {
    return min(max(degrees, 0), 180)
  }
}

/// A delegate object built at runtime for a protocol whose methods are unknown
/// at compile time.
///
/// Every protocol method is bound to the same block, which ignores its
/// arguments and just signals "something changed"; the value is then re-read
/// from the interaction. Ignoring arguments is what makes binding to an
/// unverified signature safe.
private final class DelegateProxy {
  static func make(notifying onChange: @escaping () -> Void) -> NSObject? {
    guard let proto = objc_getProtocol("UIHingeInteractionDelegate")
    else { return nil }

    let name = "FoldableHingeDelegateProxy"
    let cls: AnyClass
    if let existing = NSClassFromString(name) {
      cls = existing
    } else {
      guard let allocated = objc_allocateClassPair(NSObject.self, name, 0)
      else { return nil }
      class_addProtocol(allocated, proto)
      addProtocolMethods(to: allocated, proto: proto, onChange: onChange)
      objc_registerClassPair(allocated)
      cls = allocated
    }

    guard let type = cls as? NSObject.Type else { return nil }
    return type.init()
  }

  private static func addProtocolMethods(
    to cls: AnyClass, proto: Protocol, onChange: @escaping () -> Void
  ) {
    let block: @convention(block) () -> Void = { onChange() }
    let imp = imp_implementationWithBlock(block)

    for isRequired in [true, false] {
      var count: UInt32 = 0
      guard
        let descriptions = protocol_copyMethodDescriptionList(
          proto, isRequired, true, &count)
      else { continue }
      defer { free(descriptions) }

      for index in 0..<Int(count) {
        let description = descriptions[index]
        guard let selector = description.name, let types = description.types
        else { continue }
        class_addMethod(cls, selector, imp, types)
      }
    }
  }
}
