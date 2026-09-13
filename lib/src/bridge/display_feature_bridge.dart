import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/foundation.dart';

import '../model/hinge_status.dart';
import '../model/reserved_region.dart';

/// How much fold information is published to `MediaQuery.displayFeatures`.
///
/// Publishing is opt-in because Flutter's `DisplayFeatureSubScreen` confines
/// dialogs, sheets, popup menus and pickers to one side of any display feature
/// it considers obstructing. Eleven framework files inherit that behaviour, so
/// writing to `displayFeatures` unconditionally would mean that merely adding
/// this package to a project changes every Material surface in it.
///
/// See https://github.com/flutter/flutter/issues/192515.
enum DisplayFeatureBridgeMode {
  /// Nothing is written to `MediaQuery.displayFeatures`. Framework behaviour
  /// is completely unchanged; fold data is available only through
  /// `DuoMediaQuery`.
  ///
  /// This is the default.
  none,

  /// Only `.occlusion` regions are published, as
  /// [DisplayFeatureType.cutout].
  ///
  /// A camera cutout does not span the screen edge to edge, so it fails
  /// `DisplayFeatureSubScreen.subScreensInBounds`' split condition: dialogs
  /// keep their full width and merely avoid the camera.
  cutoutsOnly,

  /// Occlusions plus active, non-zero-width fold divisions.
  ///
  /// This deliberately engages Flutter's sub-screen splitting. Dialogs and
  /// sheets being confined to roughly one half of the inner display is the
  /// accepted consequence of this mode, not a bug. Applications choosing it
  /// should have an `anchorPoint` strategy.
  full,
}

/// Converts [ReservedRegion]s into `dart:ui` [DisplayFeature]s.
///
/// The conversion enforces four invariants that together make it impossible
/// for this package to split an application's layout by accident.
abstract final class DisplayFeatureBridge {
  /// Builds the display features to publish, or an empty list.
  ///
  /// Invariants:
  ///
  /// * **R1**: a region whose shortest side is zero is never published.
  ///   Combined with `postureHalfOpened` such a feature would still satisfy
  ///   `DisplayFeatureSubScreen.avoidBounds`, splitting the screen in two with
  ///   no visible fold. Apple's `.division` is exactly zero-width while the
  ///   device is flat, so this trap is easy to fall into.
  /// * **R2**: inactive regions are never published.
  /// * **R3**: [DisplayFeatureType.cutout] always carries
  ///   [DisplayFeatureState.unknown], which `dart:ui` asserts.
  /// * **R4**: nothing is published while the device is closed. `dart:ui` has
  ///   no `postureClosed`, and with the device shut the Flutter view runs on
  ///   the outer display, which has no fold at all.
  static List<DisplayFeature> build({
    required DisplayFeatureBridgeMode mode,
    required List<ReservedRegion> regions,
    required HingeStatus status,
  }) {
    if (mode == DisplayFeatureBridgeMode.none) {
      return const <DisplayFeature>[];
    }
    if (status == HingeStatus.closed) {
      return const <DisplayFeature>[]; // R4
    }

    final List<DisplayFeature> out = <DisplayFeature>[];

    for (final ReservedRegion region in regions) {
      if (region.kind != ReservedRegionKind.occlusion) continue;
      if (!region.isActive || region.bounds.isEmpty) continue; // R2
      out.add(
        DisplayFeature(
          bounds: region.bounds,
          type: DisplayFeatureType.cutout,
          state: DisplayFeatureState.unknown, // R3
        ),
      );
    }

    if (mode == DisplayFeatureBridgeMode.full) {
      for (final ReservedRegion region in regions) {
        if (region.kind != ReservedRegionKind.division) continue;
        if (!region.isActive) continue; // R2
        if (region.bounds.shortestSide <= 0) continue; // R1
        out.add(
          DisplayFeature(
            bounds: region.bounds,
            // `fold`, not `hinge`: the inner display is one continuous curved
            // panel with no physical gap between two separate screens.
            type: DisplayFeatureType.fold,
            state: postureFor(status),
          ),
        );
      }
    }

    assert(_debugNoSilentSplit(out));
    return List<DisplayFeature>.unmodifiable(out);
  }

  /// Maps a [HingeStatus] onto the posture `dart:ui` understands.
  ///
  /// [HingeStatus.closed] has no counterpart and is handled by R4 before this
  /// is ever reached.
  @visibleForTesting
  static DisplayFeatureState postureFor(HingeStatus status) => switch (status) {
    HingeStatus.fullyOpen => DisplayFeatureState.postureFlat,
    HingeStatus.partiallyOpen => DisplayFeatureState.postureHalfOpened,
    HingeStatus.closed => DisplayFeatureState.unknown,
    HingeStatus.unknown => DisplayFeatureState.unknown,
  };

  /// Re-implements `DisplayFeatureSubScreen.avoidBounds`' predicate locally and
  /// throws if this package ever produces a zero-area feature that would
  /// nonetheless split the screen.
  static bool _debugNoSilentSplit(List<DisplayFeature> features) {
    for (final DisplayFeature feature in features) {
      final bool wouldSplit =
          feature.bounds.shortestSide > 0 ||
          feature.state == DisplayFeatureState.postureHalfOpened;
      if (wouldSplit && feature.bounds.shortestSide <= 0) {
        throw FlutterError(
          'foldable: a zero-width DisplayFeature was about to be published '
          'with ${feature.state}. Flutter would split the screen in two with '
          'no visible fold, confining every dialog, sheet and picker to one '
          'half. This is a bug in the foldable package.',
        );
      }
    }
    return true;
  }
}
