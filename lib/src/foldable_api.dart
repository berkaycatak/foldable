import 'package:flutter/foundation.dart';

import 'model/foldable_capabilities.dart';
import 'model/foldable_data.dart';
import 'model/hinge_status.dart';
import 'platform/foldable_method_channel.dart';
import 'platform/foldable_platform.dart';

/// The entry point for reading fold state outside the widget tree.
///
/// Inside a widget tree, prefer `DuoMediaQuery` / `FoldAwareBuilder`, which
/// rebuild only the parts of the tree that care.
abstract final class Foldable {
  /// Whether this device physically has a hinge.
  ///
  /// Returns `false` on every other platform and never throws.
  static Future<bool> get isFoldable async =>
      (await FoldablePlatform.instance.getSnapshot()).isFoldable;

  /// What the platform supports, plus diagnostics about how it was resolved.
  static Future<FoldableCapabilities> get capabilities async =>
      (await FoldablePlatform.instance.getSnapshot()).capabilities;

  /// The current fold posture, read once.
  static Future<HingeStatus> get hingeStatus async =>
      (await FoldablePlatform.instance.getSnapshot()).status;

  /// The full current state, read once.
  static Future<FoldableData> get snapshot =>
      FoldablePlatform.instance.getSnapshot();

  /// Every state change, as an atomic snapshot.
  static Stream<FoldableData> get changes => FoldablePlatform.instance.events;

  /// The continuous hinge angle in **degrees**: 0° closed, 180° flat.
  ///
  /// On a device without a hinge this completes without emitting, so a
  /// `StreamBuilder` lands on [ConnectionState.done] rather than waiting
  /// forever.
  ///
  /// Apple's guidance is to drive effects and interactions from the raw angle,
  /// not layout. Use [changes] or `FoldAwareBuilder` for layout decisions.
  static Stream<double> get hingeAngleStream => FoldablePlatform.instance.events
      .map((FoldableData d) => d.angleDegrees)
      .where((double? a) => a != null)
      .cast<double>();

  /// Fold posture changes, emitted only when the posture actually changes.
  static Stream<HingeStatus> get hingeStatusStream => FoldablePlatform
      .instance
      .events
      .map((FoldableData d) => d.status)
      .distinct();

  /// Dumps the Objective-C runtime shape of the hinge APIs on the device.
  ///
  /// Apple has not published reference documentation for `UIHingeInteraction`,
  /// so this is how the real selectors and delegate signatures get confirmed.
  /// Debug aid only. Do not ship logic that depends on its shape.
  static Future<Map<String, Object?>> debugDumpNativeApi() =>
      FoldablePlatform.instance.debugDumpNativeApi();

  /// Clears cached platform state so a test can start clean.
  @visibleForTesting
  static void debugReset() {
    final FoldablePlatform platform = FoldablePlatform.instance;
    if (platform is MethodChannelFoldable) {
      platform.debugReset();
    }
  }
}
