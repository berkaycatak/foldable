import 'dart:async';
import 'dart:ui' show DisplayFeature;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';
import 'package:foldable/src/platform/foldable_codec.dart';

FoldableData dataWith({
  required SizeClass horizontal,
  SizeClass vertical = SizeClass.regular,
  bool isFoldable = true,
}) => FoldableData(
  capabilities: FoldableCapabilities(
    supportLevel: isFoldable
        ? FoldableSupportLevel.available
        : FoldableSupportLevel.unsupported,
    isFoldable: isFoldable,
    hingeApiPresent: isFoldable,
    regionApiPresent: isFoldable,
    angleUnitVerified: false,
    strategy: 'test',
  ),
  status: isFoldable ? HingeStatus.fullyOpen : HingeStatus.unknown,
  angleDegrees: isFoldable ? 180 : null,
  regions: const <ReservedRegion>[],
  displayFeatures: const <DisplayFeature>[],
  horizontalSizeClass: horizontal,
  verticalSizeClass: vertical,
);

Future<void> pushData(
  WidgetTester tester,
  StreamController<FoldableData> controller,
  FoldableData data,
) async {
  controller.add(data);
  await tester.pump();
  await tester.pump();
}

void main() {
  group('wire decoding', () {
    test('decodes both size classes', () {
      final FoldableData data = FoldableCodec.decodeSnapshot(
        const <Object?, Object?>{
          'horizontalSizeClass': 'regular',
          'verticalSizeClass': 'compact',
        },
      );
      expect(data.horizontalSizeClass, SizeClass.regular);
      expect(data.verticalSizeClass, SizeClass.compact);
    });

    test('missing or unknown values fall back to unspecified', () {
      final FoldableData missing = FoldableCodec.decodeSnapshot(
        const <Object?, Object?>{},
      );
      expect(missing.horizontalSizeClass, SizeClass.unspecified);

      final FoldableData bogus = FoldableCodec.decodeSnapshot(
        const <Object?, Object?>{'horizontalSizeClass': 'enormous'},
      );
      expect(bogus.horizontalSizeClass, SizeClass.unspecified);
    });

    test('every wire name round trips', () {
      for (final SizeClass value in SizeClass.values) {
        expect(SizeClass.fromWire(value.wireName), value);
      }
    });
  });

  group('DuoMediaQuery', () {
    testWidgets('exposes size classes', (WidgetTester tester) async {
      final StreamController<FoldableData> feed =
          StreamController<FoldableData>.broadcast();
      addTearDown(feed.close);

      late SizeClass horizontal;
      late SizeClass vertical;
      await tester.pumpWidget(
        MaterialApp(
          home: FoldableProvider(
            debugData: feed.stream,
            child: Builder(
              builder: (BuildContext context) {
                horizontal = DuoMediaQuery.horizontalSizeClassOf(context);
                vertical = DuoMediaQuery.verticalSizeClassOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await pushData(
        tester,
        feed,
        dataWith(horizontal: SizeClass.regular, vertical: SizeClass.compact),
      );

      expect(horizontal, SizeClass.regular);
      expect(vertical, SizeClass.compact);
    });

    testWidgets('posture readers ignore a size class change', (
      WidgetTester tester,
    ) async {
      final StreamController<FoldableData> feed =
          StreamController<FoldableData>.broadcast();
      addTearDown(feed.close);

      int statusBuilds = 0;
      int sizeClassBuilds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: FoldableProvider(
            debugData: feed.stream,
            child: Column(
              children: <Widget>[
                Builder(
                  builder: (BuildContext context) {
                    DuoMediaQuery.statusOf(context);
                    statusBuilds++;
                    return const SizedBox();
                  },
                ),
                Builder(
                  builder: (BuildContext context) {
                    DuoMediaQuery.horizontalSizeClassOf(context);
                    sizeClassBuilds++;
                    return const SizedBox();
                  },
                ),
              ],
            ),
          ),
        ),
      );

      await pushData(tester, feed, dataWith(horizontal: SizeClass.compact));
      final int statusBaseline = statusBuilds;
      final int sizeBaseline = sizeClassBuilds;

      // Same posture, different size class: entering Split View.
      await pushData(tester, feed, dataWith(horizontal: SizeClass.regular));

      expect(
        statusBuilds,
        statusBaseline,
        reason: 'posture reader rebuilt on a size-class-only change',
      );
      expect(sizeClassBuilds, greaterThan(sizeBaseline));
    });

    testWidgets('without a provider returns unspecified', (
      WidgetTester tester,
    ) async {
      late SizeClass seen;
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext context) {
            seen = DuoMediaQuery.horizontalSizeClassOf(context);
            return const SizedBox();
          },
        ),
      );
      expect(seen, SizeClass.unspecified);
    });
  });

  group('FoldAwareBuilder', () {
    testWidgets('reports size classes on a device without a hinge', (
      WidgetTester tester,
    ) async {
      final StreamController<FoldableData> feed =
          StreamController<FoldableData>.broadcast();
      addTearDown(feed.close);

      late FoldInfo seen;
      await tester.pumpWidget(
        MaterialApp(
          home: FoldableProvider(
            debugData: feed.stream,
            child: FoldAwareBuilder(
              builder:
                  (BuildContext context, BoxConstraints c, FoldInfo fold) {
                    seen = fold;
                    return const SizedBox.expand();
                  },
            ),
          ),
        ),
      );

      await pushData(
        tester,
        feed,
        dataWith(horizontal: SizeClass.compact, isFoldable: false),
      );

      // The hinge is absent but the size class is still real and useful.
      expect(seen.isFoldable, isFalse);
      expect(seen.horizontalSizeClass, SizeClass.compact);
      expect(seen.isRegularWidth, isFalse);
    });

    testWidgets('isRegularWidth tracks the inner display', (
      WidgetTester tester,
    ) async {
      final StreamController<FoldableData> feed =
          StreamController<FoldableData>.broadcast();
      addTearDown(feed.close);

      late FoldInfo seen;
      await tester.pumpWidget(
        MaterialApp(
          home: FoldableProvider(
            debugData: feed.stream,
            child: FoldAwareBuilder(
              builder:
                  (BuildContext context, BoxConstraints c, FoldInfo fold) {
                    seen = fold;
                    return const SizedBox.expand();
                  },
            ),
          ),
        ),
      );

      await pushData(tester, feed, dataWith(horizontal: SizeClass.regular));
      expect(seen.isRegularWidth, isTrue);
    });
  });
}
