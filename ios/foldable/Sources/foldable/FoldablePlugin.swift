import Flutter
import UIKit

/// Bridges iPhone Duo hinge state to Flutter.
public class FoldablePlugin: NSObject, FlutterPlugin {

  private static let methodChannelName = "foldable/methods"
  private static let eventChannelName = "foldable/events"
  private static let wireVersion = 1

  private let hingeSource: HingeSource
  private let regionSource: RegionSource
  private var streamHandler: HingeStreamHandler?

  override init() {
    hingeSource = FoldableSourceFactory.makeHingeSource()
    regionSource = FoldableSourceFactory.makeRegionSource()
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FoldablePlugin()

    let methods = FlutterMethodChannel(
      name: methodChannelName, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methods)

    let handler = HingeStreamHandler(
      hingeSource: instance.hingeSource,
      snapshotBuilder: { [weak instance] reading in
        instance?.snapshot(with: reading) ?? [:]
      })
    instance.streamHandler = handler

    let events = FlutterEventChannel(
      name: eventChannelName, binaryMessenger: registrar.messenger())
    events.setStreamHandler(handler)

    // Installing the interaction early matters: the platform only reveals
    // whether this device has a hinge through an update, so without an
    // interaction already running, the first getSnapshot would have to answer
    // "unknown" and Dart would have nothing to go on.
    registrar.addApplicationDelegate(instance)
    instance.installInteractionWhenPossible()

    registrar.publish(instance)
  }

  public func applicationDidBecomeActive(_ application: UIApplication) {
    installInteractionWhenPossible()
  }

  /// Attaches the hinge interaction to the Flutter view once one exists.
  ///
  /// Retried rather than done once, because at registration time the window
  /// may not have a root view yet.
  func installInteractionWhenPossible() {
    guard let view = Self.hostView() else {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
        guard let self = self, Self.hostView() != nil else { return }
        self.installInteractionWhenPossible()
      }
      return
    }
    hingeSource.start(on: view) { [weak self] reading in
      self?.streamHandler?.emit(reading)
      self?.settleRegions(after: reading)
    }
  }

  // MARK: - Region settling

  /// Bumped on every hinge update so an older poll stops itself.
  private var settleGeneration = 0
  private static let settleInterval: TimeInterval = 0.1
  private static let settleAttempts = 20

  /// Re-emits once the fold division agrees with the hinge.
  ///
  /// Reserved regions lag the hinge and nothing announces when they catch up.
  /// Measured on the iPhone Duo simulator: inside the update handler the
  /// division still has its pre-move `isActive`; laying the device flat it
  /// clears a few milliseconds later, and folding it only sets about a second
  /// later, once the hinge comes to rest. The view's bounds do not change, so
  /// no layout pass or further hinge update arrives to correct the snapshot.
  private func settleRegions(after reading: HingeReading) {
    settleGeneration += 1
    let expectedActive: Bool
    switch reading.status {
    case .partiallyOpen: expectedActive = true
    case .fullyOpen: expectedActive = false
    default: return
    }
    pollRegions(
      generation: settleGeneration, expectedActive: expectedActive, reading: reading,
      attemptsLeft: Self.settleAttempts)
  }

  private func pollRegions(
    generation: Int, expectedActive: Bool, reading: HingeReading, attemptsLeft: Int
  ) {
    guard attemptsLeft > 0 else { return }
    // No division at all means an SDK or a window without one: nothing to wait for.
    guard let division = regions(in: Self.hostView()).first(where: { $0.kind == .division })
    else { return }
    if division.isActive == expectedActive {
      // Already consistent on the first look means the emit that preceded this
      // call carried the right regions.
      if attemptsLeft < Self.settleAttempts { streamHandler?.emit(reading) }
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleInterval) { [weak self] in
      guard let self = self, self.settleGeneration == generation else { return }
      self.pollRegions(
        generation: generation, expectedActive: expectedActive, reading: reading,
        attemptsLeft: attemptsLeft - 1)
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getSnapshot":
      installInteractionWhenPossible()
      result(snapshot(with: hingeSource.currentReading))
    case "debugDumpNativeApi":
      result(FoldableDiagnostics.dump())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Snapshot

  func snapshot(with reading: HingeReading?) -> [String: Any] {
    let hingeApi = FoldableSourceFactory.hingeApiPresent
    let regionApi = FoldableSourceFactory.regionApiPresent
    let hasHinge = hingeSource.hasHinge

    // `hasHinge` is nil until the first update lands. Reporting that as
    // "unsupported" would be a lie that Dart cannot recover from, so it is
    // reported as unknown and Dart keeps the stream open until it is settled.
    let supportLevel: String
    if !hingeApi {
      supportLevel = "unsupported"
    } else if hasHinge == true {
      supportLevel = "available"
    } else if hasHinge == false {
      supportLevel = "availableNoHinge"
    } else {
      supportLevel = "unknown"
    }

    let view = Self.hostView()
    let sizeClasses = FoldableTraits.sizeClasses(for: view)

    var payload: [String: Any] = [
      "wireVersion": Self.wireVersion,
      "supportLevel": supportLevel,
      "isFoldable": hasHinge == true,
      "hingeApiPresent": hingeApi,
      "regionApiPresent": regionApi,
      "angleUnitVerified": reading?.angleUnitVerified ?? false,
      "strategy": hingeSource.strategy,
      "status": (reading?.status ?? .unknown).rawValue,
      "regions": regions(in: view).map { $0.toMap() },
      "horizontalSizeClass": sizeClasses.horizontal.rawValue,
      "verticalSizeClass": sizeClasses.vertical.rawValue,
    ]
    payload["angleDegrees"] = reading?.angleDegrees ?? NSNull()
    return payload
  }

  private func regions(in view: UIView?) -> [FoldableRegion] {
    guard let view = view else { return [] }
    return regionSource.regions(in: view)
  }

  /// The view the interaction attaches to and regions are read from.
  static func hostView() -> UIView? {
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene,
        windowScene.activationState == .foregroundActive
          || windowScene.activationState == .foregroundInactive
      else { continue }
      let window =
        windowScene.windows.first(where: { $0.isKeyWindow })
        ?? windowScene.windows.first
      if let view = window?.rootViewController?.view ?? window {
        return view
      }
    }
    return nil
  }
}

/// Streams hinge snapshots to Dart.
final class HingeStreamHandler: NSObject, FlutterStreamHandler {

  private let hingeSource: HingeSource
  private let snapshotBuilder: (HingeReading?) -> [String: Any]
  private var sink: FlutterEventSink?

  init(
    hingeSource: HingeSource,
    snapshotBuilder: @escaping (HingeReading?) -> [String: Any]
  ) {
    self.hingeSource = hingeSource
    self.snapshotBuilder = snapshotBuilder
    super.init()
  }

  /// Starts streaming, or closes the stream cleanly.
  ///
  /// Never returns a `FlutterError`: Dart reports an EventChannel activation
  /// failure through `FlutterError.reportError` rather than the stream, so an
  /// error here would leave the listener with no data, no error and no
  /// completion. `FlutterEndOfEventStream` gives a clean `onDone` instead.
  func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    sink = events

    guard FoldableSourceFactory.hingeApiPresent else {
      events(FlutterEndOfEventStream)
      return nil
    }

    if let current = hingeSource.currentReading {
      events(snapshotBuilder(current))
      // Already settled as "no hinge": nothing further will ever arrive.
      if hingeSource.hasHinge == false {
        events(FlutterEndOfEventStream)
      }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  /// Forwards an update, and closes the stream once it is known there is no
  /// hinge, so a listener is never left waiting on a device that has none.
  func emit(_ reading: HingeReading?) {
    guard let sink = sink else { return }
    let payload = snapshotBuilder(reading)
    let settledWithoutHinge = hingeSource.hasHinge == false
    let deliver = {
      sink(payload)
      if settledWithoutHinge { sink(FlutterEndOfEventStream) }
    }
    if Thread.isMainThread {
      deliver()
    } else {
      DispatchQueue.main.async(execute: deliver)
    }
  }
}
