#if FOLDABLE_NATIVE_API

  import UIKit

  // Compiled only when FOLDABLE_NATIVE_API is defined, which requires an SDK
  // that declares the hinge APIs (iOS 27.1 / Xcode 27.1). Without the flag the
  // runtime sources carry the feature and the package still builds against
  // older SDKs at an iOS 13 deployment target.
  //
  // To enable:
  //   * Package.swift    uncomment .define("FOLDABLE_NATIVE_API")
  //   * foldable.podspec uncomment the OTHER_SWIFT_FLAGS line
  //
  // Both paths report identical readings; this one just lets the compiler
  // check the shapes instead of the runtime.

  /// Hinge readings from the real `UIHingeInteraction`.
  @available(iOS 27.1, *)
  final class NativeHingeSource: NSObject, HingeSource {
    static var isAvailable: Bool { return true }

    private var interaction: UIHingeInteraction?
    private weak var attachedView: UIView?
    private var onChange: ((HingeReading) -> Void)?
    private var latest: HingeReading?
    private var knownHasHinge: Bool?

    var strategy: String { return "native" }
    var currentReading: HingeReading? { return latest }
    var hasHinge: Bool? { return knownHasHinge }

    @discardableResult
    func start(on view: UIView, onChange: @escaping (HingeReading) -> Void) -> Bool {
      self.onChange = onChange
      if interaction != nil { return true }

      let created = UIHingeInteraction { [weak self] _, update in
        self?.handle(update)
      }
      view.addInteraction(created)
      interaction = created
      attachedView = view
      return true
    }

    func stop() {
      if let interaction = interaction, let view = attachedView {
        view.removeInteraction(interaction)
      }
      interaction = nil
      attachedView = nil
      onChange = nil
    }

    private func handle(_ update: UIHingeInteraction.Update) {
      // A nil hinge means this device has none, or the interaction left a
      // hierarchy that provides hinge updates.
      guard let hinge = update.hinge else {
        knownHasHinge = false
        latest = HingeReading.none
        onChange?(HingeReading.none)
        return
      }

      knownHasHinge = true
      let status: FoldableHingeStatus
      switch hinge.status {
      case .closed: status = .closed
      case .partiallyOpen: status = .partiallyOpen
      case .fullyOpen: status = .fullyOpen
      default: status = .unknown
      }

      // `hinge.angle` is documented as radians.
      let degrees = min(max(Double(hinge.angle) * 180.0 / Double.pi, 0), 180)
      let reading = HingeReading(
        status: status, angleDegrees: degrees, angleUnitVerified: true)
      latest = reading
      onChange?(reading)
    }
  }

  /// Reserved regions from the real `reservedRegions(kind:options:)`.
  @available(iOS 27.1, *)
  final class NativeRegionSource: RegionSource {
    static var isAvailable: Bool { return true }

    func regions(in view: UIView) -> [FoldableRegion] {
      var result: [FoldableRegion] = []
      // The fold is inactive and zero width while flat, so it is requested
      // with .includeInactive; an occlusion is only active while that camera
      // is in use, so an inactive one carries no information.
      result += view.reservedRegions(kind: .division, options: .includeInactive)
        .map { FoldableRegion(kind: .division, frame: $0.frame, isActive: $0.isActive) }
      result += view.reservedRegions(kind: .occlusion)
        .map { FoldableRegion(kind: .occlusion, frame: $0.frame, isActive: $0.isActive) }
      return result
    }
  }

#endif
