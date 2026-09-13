import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';

/// The inner display of an iPhone Duo in logical pixels (1878x2670 @3x).
const Size kInnerDisplay = Size(626, 890);

ReservedRegion division({
  required bool active,
  double thickness = 40,
}) => ReservedRegion(
  kind: ReservedRegionKind.division,
  bounds: Rect.fromLTWH(
    (kInnerDisplay.width - thickness) / 2,
    0,
    thickness,
    kInnerDisplay.height,
  ),
  isActive: active,
);

const ReservedRegion occlusion = ReservedRegion(
  kind: ReservedRegionKind.occlusion,
  bounds: Rect.fromLTWH(283, 0, 60, 30),
  isActive: true,
);

void main() {
  group('mode: none', () {
    test('publishes nothing regardless of input', () {
      for (final HingeStatus status in HingeStatus.values) {
        expect(
          DisplayFeatureBridge.build(
            mode: DisplayFeatureBridgeMode.none,
            regions: <ReservedRegion>[division(active: true), occlusion],
            status: status,
          ),
          isEmpty,
          reason: 'status $status leaked a feature in mode none',
        );
      }
    });
  });

  group('R1 - silent split protection', () {
    test('zero-width active division is never published', () {
      final List<DisplayFeature> features = DisplayFeatureBridge.build(
        mode: DisplayFeatureBridgeMode.full,
        regions: <ReservedRegion>[division(active: true, thickness: 0)],
        status: HingeStatus.partiallyOpen,
      );
      expect(features, isEmpty);
    });

    test(
      'zero-width division would otherwise satisfy avoidBounds - proof',
      () {
        // Demonstrates the trap R1 exists to prevent: a zero-width feature in
        // postureHalfOpened passes the framework predicate and splits the
        // screen with no visible fold.
        final MediaQueryData trap = MediaQueryData(
          size: kInnerDisplay,
          displayFeatures: <DisplayFeature>[
            DisplayFeature(
              bounds: Rect.fromLTRB(313, 0, 313, kInnerDisplay.height),
              type: DisplayFeatureType.fold,
              state: DisplayFeatureState.postureHalfOpened,
            ),
          ],
        );
        expect(DisplayFeatureSubScreen.avoidBounds(trap), hasLength(1));
      },
    );
  });

  group('R2 - inactive regions', () {
    test('inactive division is not published even when wide', () {
      expect(
        DisplayFeatureBridge.build(
          mode: DisplayFeatureBridgeMode.full,
          regions: <ReservedRegion>[division(active: false)],
          status: HingeStatus.fullyOpen,
        ),
        isEmpty,
      );
    });
  });

  group('R3 - cutout state', () {
    test('occlusion becomes a cutout carrying state unknown', () {
      final List<DisplayFeature> features = DisplayFeatureBridge.build(
        mode: DisplayFeatureBridgeMode.cutoutsOnly,
        regions: <ReservedRegion>[occlusion, division(active: true)],
        status: HingeStatus.partiallyOpen,
      );
      expect(features, hasLength(1));
      expect(features.single.type, DisplayFeatureType.cutout);
      // dart:ui asserts this pairing; a violation would throw in the ctor.
      expect(features.single.state, DisplayFeatureState.unknown);
    });

    test('cutoutsOnly never publishes the fold', () {
      final List<DisplayFeature> features = DisplayFeatureBridge.build(
        mode: DisplayFeatureBridgeMode.cutoutsOnly,
        regions: <ReservedRegion>[division(active: true)],
        status: HingeStatus.partiallyOpen,
      );
      expect(features, isEmpty);
    });
  });

  group('R4 - closed device', () {
    test('publishes nothing in every mode', () {
      for (final DisplayFeatureBridgeMode mode
          in DisplayFeatureBridgeMode.values) {
        expect(
          DisplayFeatureBridge.build(
            mode: mode,
            regions: <ReservedRegion>[division(active: true), occlusion],
            status: HingeStatus.closed,
          ),
          isEmpty,
          reason: 'mode $mode leaked a feature while closed',
        );
      }
    });
  });

  group('mode: full', () {
    test('active division maps to fold + postureHalfOpened', () {
      final List<DisplayFeature> features = DisplayFeatureBridge.build(
        mode: DisplayFeatureBridgeMode.full,
        regions: <ReservedRegion>[division(active: true)],
        status: HingeStatus.partiallyOpen,
      );
      expect(features, hasLength(1));
      // `fold`, not `hinge`: one continuous curved panel, no physical gap.
      expect(features.single.type, DisplayFeatureType.fold);
      expect(features.single.state, DisplayFeatureState.postureHalfOpened);
    });

    test('fully open maps to postureFlat', () {
      final List<DisplayFeature> features = DisplayFeatureBridge.build(
        mode: DisplayFeatureBridgeMode.full,
        regions: <ReservedRegion>[division(active: true)],
        status: HingeStatus.fullyOpen,
      );
      expect(features.single.state, DisplayFeatureState.postureFlat);
    });

    test('framework splits the screen into two halves', () {
      final MediaQueryData data = MediaQueryData(
        size: kInnerDisplay,
        displayFeatures: DisplayFeatureBridge.build(
          mode: DisplayFeatureBridgeMode.full,
          regions: <ReservedRegion>[division(active: true)],
          status: HingeStatus.partiallyOpen,
        ),
      );
      final Iterable<Rect> avoid = DisplayFeatureSubScreen.avoidBounds(data);
      expect(avoid, hasLength(1));

      final Iterable<Rect> subScreens =
          DisplayFeatureSubScreen.subScreensInBounds(
            Offset.zero & kInnerDisplay,
            avoid,
          );
      expect(subScreens, hasLength(2));
      // Each half is ~47% of the 626pt inner display.
      for (final Rect sub in subScreens) {
        expect(sub.width, closeTo(293, 0.01));
      }
    });

    test('result is unmodifiable', () {
      final List<DisplayFeature> features = DisplayFeatureBridge.build(
        mode: DisplayFeatureBridgeMode.full,
        regions: <ReservedRegion>[division(active: true)],
        status: HingeStatus.fullyOpen,
      );
      expect(() => features.add(features.first), throwsUnsupportedError);
    });
  });

  group('posture mapping', () {
    test('covers every HingeStatus without throwing', () {
      expect(
        DisplayFeatureBridge.postureFor(HingeStatus.fullyOpen),
        DisplayFeatureState.postureFlat,
      );
      expect(
        DisplayFeatureBridge.postureFor(HingeStatus.partiallyOpen),
        DisplayFeatureState.postureHalfOpened,
      );
      // dart:ui has no postureClosed - both fall back to unknown.
      expect(
        DisplayFeatureBridge.postureFor(HingeStatus.closed),
        DisplayFeatureState.unknown,
      );
      expect(
        DisplayFeatureBridge.postureFor(HingeStatus.unknown),
        DisplayFeatureState.unknown,
      );
    });
  });
}
