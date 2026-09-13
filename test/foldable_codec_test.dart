import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';
import 'package:foldable/src/platform/foldable_codec.dart';

const Map<String, Object?> kFoldablePayload = <String, Object?>{
  'wireVersion': 1,
  'supportLevel': 'available',
  'isFoldable': true,
  'hingeApiPresent': true,
  'regionApiPresent': true,
  'angleUnitVerified': false,
  'strategy': 'interactionKVO',
  'status': 'partiallyOpen',
  'angleDegrees': 97.4,
  'regions': <Map<String, Object?>>[
    <String, Object?>{
      'kind': 'division',
      'active': true,
      'left': 293.0,
      'top': 0.0,
      'width': 40.0,
      'height': 890.0,
    },
  ],
};

void main() {
  group('decodeSnapshot', () {
    test('decodes a full payload', () {
      final FoldableData data = FoldableCodec.decodeSnapshot(kFoldablePayload);

      expect(data.isFoldable, isTrue);
      expect(data.status, HingeStatus.partiallyOpen);
      expect(data.angleDegrees, 97.4);
      expect(data.capabilities.supportLevel, FoldableSupportLevel.available);
      expect(data.capabilities.strategy, 'interactionKVO');
      expect(data.capabilities.angleUnitVerified, isFalse);
      expect(data.regions, hasLength(1));
      expect(data.regions.single.kind, ReservedRegionKind.division);
      expect(data.regions.single.bounds, const Rect.fromLTWH(293, 0, 40, 890));
      expect(data.regions.single.isActive, isTrue);
      // Bridging is a Dart-side decision; the platform never supplies these.
      expect(data.displayFeatures, isEmpty);
    });

    test('null payload yields unsupported instead of throwing', () {
      expect(FoldableCodec.decodeSnapshot(null), FoldableData.unsupported);
    });

    test('empty map degrades to safe defaults', () {
      final FoldableData data = FoldableCodec.decodeSnapshot(
        const <Object?, Object?>{},
      );
      expect(data.isFoldable, isFalse);
      expect(data.status, HingeStatus.unknown);
      expect(data.angleDegrees, isNull);
      expect(data.regions, isEmpty);
      expect(data.capabilities.strategy, 'none');
    });

    test('integer angle does not crash the num cast', () {
      // The standard codec sends a whole number as Int32, so `as double`
      // would throw here. This is the most likely first-day bug.
      final FoldableData data = FoldableCodec.decodeSnapshot(
        <Object?, Object?>{'isFoldable': true, 'angleDegrees': 90},
      );
      expect(data.angleDegrees, 90.0);
      expect(data.angleDegrees, isA<double>());
    });

    test('integer region bounds are accepted', () {
      final FoldableData data = FoldableCodec.decodeSnapshot(
        <Object?, Object?>{
          'regions': <Map<String, Object?>>[
            <String, Object?>{
              'kind': 'occlusion',
              'active': true,
              'left': 283,
              'top': 0,
              'width': 60,
              'height': 30,
            },
          ],
        },
      );
      expect(data.regions.single.bounds, const Rect.fromLTWH(283, 0, 60, 30));
    });

    test('unknown status and kind strings fall back, never throw', () {
      final FoldableData data = FoldableCodec.decodeSnapshot(
        <Object?, Object?>{
          'status': 'tentMode',
          'regions': <Map<String, Object?>>[
            <String, Object?>{
              'kind': 'somethingNew',
              'active': true,
              'left': 0.0,
              'top': 0.0,
              'width': 1.0,
              'height': 1.0,
            },
          ],
        },
      );
      expect(data.status, HingeStatus.unknown);
      expect(data.regions.single.kind, ReservedRegionKind.unknown);
    });

    test('region with missing geometry is dropped, siblings survive', () {
      final FoldableData data = FoldableCodec.decodeSnapshot(
        <Object?, Object?>{
          'regions': <Object?>[
            <String, Object?>{'kind': 'division', 'active': true},
            'not a map',
            <String, Object?>{
              'kind': 'occlusion',
              'active': true,
              'left': 0.0,
              'top': 0.0,
              'width': 10.0,
              'height': 10.0,
            },
          ],
        },
      );
      expect(data.regions, hasLength(1));
      expect(data.regions.single.kind, ReservedRegionKind.occlusion);
    });

    test('non-list regions value is tolerated', () {
      final FoldableData data = FoldableCodec.decodeSnapshot(
        <Object?, Object?>{'regions': 'oops'},
      );
      expect(data.regions, isEmpty);
    });
  });

  group('wire round trip', () {
    test('every enum wire name decodes back to itself', () {
      for (final HingeStatus status in HingeStatus.values) {
        expect(HingeStatus.fromWire(status.wireName), status);
      }
      for (final ReservedRegionKind kind in ReservedRegionKind.values) {
        expect(ReservedRegionKind.fromWire(kind.wireName), kind);
      }
      for (final FoldableSupportLevel level in FoldableSupportLevel.values) {
        expect(FoldableSupportLevel.fromWire(level.wireName), level);
      }
    });
  });
}
