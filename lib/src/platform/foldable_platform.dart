import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../model/foldable_data.dart';
import 'foldable_method_channel.dart';

/// The interface every platform implementation of `foldable` conforms to.
///
/// Exists even though only iOS is implemented today: it lets the widget and
/// bridge layers be driven by a fake in tests, without touching a channel.
abstract class FoldablePlatform extends PlatformInterface {
  /// Constructs a platform implementation.
  FoldablePlatform() : super(token: _token);

  static final Object _token = Object();

  static FoldablePlatform _instance = MethodChannelFoldable();

  /// The active implementation.
  static FoldablePlatform get instance => _instance;

  /// Replaces the active implementation.
  static set instance(FoldablePlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Reads the current state once.
  ///
  /// This, never the event stream, is the authoritative source for
  /// capability detection: `EventChannel` swallows activation errors, so a
  /// silent stream cannot be distinguished from a missing plugin.
  ///
  /// Implementations must never throw; unreachable platforms return
  /// [FoldableData.unsupported].
  Future<FoldableData> getSnapshot() {
    throw UnimplementedError('getSnapshot() has not been implemented.');
  }

  /// A broadcast stream of state changes.
  ///
  /// On a device without a hinge the stream completes without emitting, so
  /// listeners receive `onDone` rather than hanging forever.
  Stream<FoldableData> get events {
    throw UnimplementedError('events has not been implemented.');
  }

  /// Dumps the Objective-C runtime shape of the hinge APIs, for diagnostics.
  ///
  /// Apple's reference documentation for `UIHingeInteraction` is not published
  /// yet, so this is how real signatures get confirmed from a real device.
  Future<Map<String, Object?>> debugDumpNativeApi() {
    throw UnimplementedError('debugDumpNativeApi() has not been implemented.');
  }
}
