import Foundation
import ObjectiveC
import UIKit

/// Reads the hinge through the Objective-C runtime.
///
/// The real API, confirmed against the iOS 27.1 SDK headers:
///
/// ```objc
/// @interface UIHingeInteraction : NSObject <UIInteraction>
/// - (instancetype)initWithUpdateHandler:
///     (void(^)(UIHingeInteraction *, UIHingeInteractionUpdate *))updateHandler
///     NS_DESIGNATED_INITIALIZER;   // init and new are NS_UNAVAILABLE
/// @end
///
/// @interface UIHingeInteractionUpdate : NSObject
/// @property (readonly, nullable) UIHinge *hinge;   // nil: no hinge here
/// @end
///
/// @interface UIHinge : NSObject
/// @property (readonly) UIHingeStatus status;  // unknown 0, closed 1,
/// @property (readonly) CGFloat angle;         // partiallyOpen 2, fullyOpen 3
/// @end                                        // angle is in RADIANS
/// ```
///
/// None of those types are named in Swift source here, so this file still
/// compiles against older SDKs and keeps the deployment target at iOS 13. On a
/// device without the API the class lookup fails and the source reports that it
/// could not start, which the plugin turns into a closed Dart stream.
final class RuntimeHingeSource: NSObject, HingeSource {

  private static let interactionClass = "UIHingeInteraction"
  private static let initSelector = "initWithUpdateHandler:"

  private var interaction: NSObject?
  private weak var attachedView: UIView?
  private var onChange: ((HingeReading) -> Void)?
  private var latest: HingeReading?
  private var knownHasHinge: Bool?

  static var isAvailable: Bool {
    guard let cls = NSClassFromString(interactionClass) else { return false }
    return cls.instancesRespond(to: NSSelectorFromString(initSelector))
  }

  var strategy: String { return "updateHandler" }
  var currentReading: HingeReading? { return latest }

  /// Unknown until the first update arrives, since the platform reports the
  /// absence of a hinge as a nil `hinge` on an update rather than as a
  /// property that can be read up front.
  var hasHinge: Bool? { return knownHasHinge }

  @discardableResult
  func start(on view: UIView, onChange: @escaping (HingeReading) -> Void) -> Bool {
    self.onChange = onChange
    if interaction != nil { return true }

    // The block is called as (interaction, update); only the update is used.
    let handler: @convention(block) (AnyObject?, AnyObject?) -> Void = {
      [weak self] _, update in
      self?.handle(update)
    }

    guard
      let created = ObjCRuntimeSupport.makeObject(
        className: Self.interactionClass,
        initSelector: Self.initSelector,
        argument: handler as AnyObject)
    else { return false }

    // addInteraction crashes on an object that does not conform, and the
    // conformance cannot be checked at compile time here.
    guard
      ObjCRuntimeSupport.conforms(
        type(of: created), toProtocolNamed: "UIInteraction")
    else { return false }

    view.addInteraction(unsafeBitCast(created, to: UIInteraction.self))
    interaction = created
    attachedView = view
    return true
  }

  func stop() {
    if let interaction = interaction, let view = attachedView,
      ObjCRuntimeSupport.conforms(
        type(of: interaction), toProtocolNamed: "UIInteraction")
    {
      view.removeInteraction(unsafeBitCast(interaction, to: UIInteraction.self))
    }
    interaction = nil
    attachedView = nil
    onChange = nil
  }

  // MARK: - Reading an update

  private func handle(_ update: AnyObject?) {
    guard let update = update as? NSObject else { return }

    // A nil hinge means this device has none, or the interaction left a
    // hierarchy that provides hinge updates.
    guard let hinge = ObjCRuntimeSupport.value(from: update, keyPath: "hinge")
      as? NSObject
    else {
      knownHasHinge = false
      let reading = HingeReading.none
      latest = reading
      onChange?(reading)
      return
    }

    knownHasHinge = true
    let reading = HingeReading(
      status: Self.status(from: hinge),
      angleDegrees: Self.angleDegrees(from: hinge),
      // The unit is documented in the SDK header as radians, so the
      // conversion below is no longer a guess.
      angleUnitVerified: true)
    latest = reading
    onChange?(reading)
  }

  /// Maps `UIHingeStatus`, whose raw values start at 1 for `closed`.
  private static func status(from hinge: NSObject) -> FoldableHingeStatus {
    guard let raw = ObjCRuntimeSupport.value(from: hinge, keyPath: "status")
      as? NSNumber
    else { return .unknown }
    switch raw.intValue {
    case 1: return .closed
    case 2: return .partiallyOpen
    case 3: return .fullyOpen
    default: return .unknown  // 0 is UIHingeStatusUnknown
    }
  }

  /// Converts `hinge.angle`, documented as radians, into degrees.
  private static func angleDegrees(from hinge: NSObject) -> Double? {
    guard let raw = ObjCRuntimeSupport.value(from: hinge, keyPath: "angle")
      as? NSNumber
    else { return nil }
    let degrees = raw.doubleValue * 180.0 / Double.pi
    return min(max(degrees, 0), 180)
  }
}
