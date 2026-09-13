import Flutter
import UIKit

/// Bridges iPhone Duo hinge state to Flutter.
public class FoldablePlugin: NSObject, FlutterPlugin {

  private static let methodChannelName = "foldable/methods"
  private static let eventChannelName = "foldable/events"

  /// The wire schema version, matched by the Dart codec.
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
      regionSource: instance.regionSource,
      snapshotBuilder: { [weak instance] reading in
        instance?.snapshot(with: reading) ?? [:]
      })
    instance.streamHandler = handler

    let events = FlutterEventChannel(
      name: eventChannelName, binaryMessenger: registrar.messenger())
    events.setStreamHandler(handler)

    registrar.publish(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getSnapshot":
      result(snapshot(with: hingeSource.currentReading))
    case "debugDumpNativeApi":
      result(FoldableDiagnostics.dump())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Snapshot

  /// Builds the payload shared by `getSnapshot` and every stream event.
  func snapshot(with reading: HingeReading?) -> [String: Any] {
    let hasHinge = hingeSource.hasHinge
    let hingeApi = FoldableSourceFactory.hingeApiPresent
    let regionApi = FoldableSourceFactory.regionApiPresent

    let supportLevel: String
    if !hingeApi {
      supportLevel = "unsupported"
    } else if hasHinge {
      supportLevel = "available"
    } else {
      supportLevel = "availableNoHinge"
    }

    let view = Self.hostView()
    let sizeClasses = FoldableTraits.sizeClasses(for: view)

    var payload: [String: Any] = [
      "wireVersion": Self.wireVersion,
      "supportLevel": supportLevel,
      "isFoldable": hasHinge,
      "hingeApiPresent": hingeApi,
      "regionApiPresent": regionApi,
      "angleUnitVerified": reading?.angleUnitVerified ?? false,
      "strategy": hingeSource.strategy,
      "status": (reading?.status ?? .unknown).rawValue,
      "regions": regions(in: view).map { $0.toMap() },
      // Size classes are available on every device, hinge or not.
      "horizontalSizeClass": sizeClasses.horizontal.rawValue,
      "verticalSizeClass": sizeClasses.vertical.rawValue,
    ]
    // NSNull encodes as Dart null; omitting the key would too, but being
    // explicit keeps the payload shape stable.
    payload["angleDegrees"] = reading?.angleDegrees ?? NSNull()
    return payload
  }

  private func regions(in view: UIView?) -> [FoldableRegion] {
    guard let view = view else { return [] }
    return regionSource.regions(in: view)
  }

  /// Finds the view the plugin attaches to.
  ///
  /// `FlutterPluginRegistrar` does not expose one, so it is resolved from the
  /// active scene and held weakly by the caller.
  static func hostView() -> UIView? {
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene,
        windowScene.activationState == .foregroundActive
          || windowScene.activationState == .foregroundInactive
      else { continue }
      if let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) {
        return keyWindow.rootViewController?.view ?? keyWindow
      }
      if let window = windowScene.windows.first {
        return window.rootViewController?.view ?? window
      }
    }
    return nil
  }
}

/// Streams hinge snapshots to Dart.
final class HingeStreamHandler: NSObject, FlutterStreamHandler {

  private let hingeSource: HingeSource
  private let regionSource: RegionSource
  private let snapshotBuilder: (HingeReading?) -> [String: Any]
  private var sink: FlutterEventSink?

  init(
    hingeSource: HingeSource,
    regionSource: RegionSource,
    snapshotBuilder: @escaping (HingeReading?) -> [String: Any]
  ) {
    self.hingeSource = hingeSource
    self.regionSource = regionSource
    self.snapshotBuilder = snapshotBuilder
    super.init()
  }

  /// Starts streaming, or closes the stream cleanly.
  ///
  /// This deliberately never returns a `FlutterError`. Dart reports an
  /// EventChannel activation failure through `FlutterError.reportError`
  /// instead of the stream, so an error here would leave the listener with no
  /// data, no error and no completion, so it hangs forever. Sending
  /// `FlutterEndOfEventStream` instead gives a device without a hinge a clean
  /// `onDone`, which is the contract the Dart side documents.
  func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    sink = events

    guard let view = FoldablePlugin.hostView(), hingeSource.hasHinge else {
      events(FlutterEndOfEventStream)
      return nil
    }

    let started = hingeSource.start(on: view) { [weak self] reading in
      self?.emit(reading)
    }

    guard started else {
      events(FlutterEndOfEventStream)
      return nil
    }

    // Replay the current state so a listener is not blank until the hinge
    // next moves.
    emit(hingeSource.currentReading)
    return nil
  }

  /// Stops streaming.
  ///
  /// May be called with `nil` arguments to separate two consecutive setups
  /// during hot restart, so it is idempotent.
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    hingeSource.stop()
    sink = nil
    return nil
  }

  private func emit(_ reading: HingeReading?) {
    guard let sink = sink else { return }
    let payload = snapshotBuilder(reading)
    if Thread.isMainThread {
      sink(payload)
    } else {
      DispatchQueue.main.async { sink(payload) }
    }
  }
}
