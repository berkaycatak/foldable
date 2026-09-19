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
    }
    observeRegionLayout(in: view)
  }

  // MARK: - Region changes

  private weak var regionObserver: RegionLayoutObserver?
  private var lastRegionSignature = ""

  /// Re-emits when a reserved region changes.
  ///
  /// Reserved regions lag the hinge: inside the update handler the fold
  /// division still has its pre-move `isActive`, and the view's bounds do not
  /// change while folding. UIKit has no notification for regions; what it does
  /// is track a region read made during layout and run layout again when that
  /// region changes. Measured on the iPhone Duo simulator, that pass follows
  /// every change of the division, and none follows when the regions are only
  /// read outside layout. So a view with no content reads them in its
  /// `layoutSubviews`, which is all it takes.
  private func observeRegionLayout(in host: UIView) {
    guard regionObserver == nil else { return }
    let observer = RegionLayoutObserver(frame: host.bounds)
    observer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    observer.isUserInteractionEnabled = false
    observer.onLayout = { [weak self] view in
      guard let self = self else { return }
      let signature = self.regions(in: view)
        .map { "\($0.kind.rawValue):\($0.isActive):\($0.frame)" }
        .joined(separator: "|")
      guard signature != self.lastRegionSignature else { return }
      self.lastRegionSignature = signature
      // A device that has settled as having no hinge has already had its
      // stream closed; there is nothing left to tell it.
      guard self.hingeSource.hasHinge != false else { return }
      self.streamHandler?.emit(self.hingeSource.currentReading)
    }
    host.insertSubview(observer, at: 0)
    regionObserver = observer
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

/// Draws nothing and takes no touches. It exists so that the reserved regions
/// are read during a layout pass, which is what makes UIKit run layout again
/// when one of them changes.
private final class RegionLayoutObserver: UIView {
  var onLayout: ((UIView) -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    onLayout?(self)
  }
}
