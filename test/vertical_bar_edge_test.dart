import 'dart:async';
import 'dart:ui' show DisplayFeature;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';
import 'package:foldable/src/platform/foldable_codec.dart';

FoldableData dataWith({
  required VerticalBarEdge edge,
  SizeClass horizontal = SizeClass.compact,
}) => FoldableData(
  capabilities: const FoldableCapabilities(
    supportLevel: FoldableSupportLevel.available,
    isFoldable: true,
    hingeApiPresent: true,
    regionApiPresent: true,
    angleUnitVerified: false,
    strategy: 'test',
  ),
  status: HingeStatus.closed,
  angleDegrees: 0,
  regions: const <ReservedRegion>[],
  displayFeatures: const <DisplayFeature>[],
  horizontalSizeClass: horizontal,
  verticalSizeClass: SizeClass.regular,
  verticalBarEdge: edge,
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
    test('decodes each edge', () {
      for (final String wire in <String>['none', 'left', 'right']) {
        final FoldableData data = FoldableCodec.decodeSnapshot(
          <Object?, Object?>{'verticalBarEdge': wire},
        );
        expect(data.verticalBarEdge.wireName, wire);
      }
    });

    test('missing or unknown values fall back to unknown', () {
      final FoldableData missing = FoldableCodec.decodeSnapshot(
        const <Object?, Object?>{},
      );
      expect(missing.verticalBarEdge, VerticalBarEdge.unknown);

      final FoldableData bogus = FoldableCodec.decodeSnapshot(
        const <Object?, Object?>{'verticalBarEdge': 'leading'},
      );
      expect(bogus.verticalBarEdge, VerticalBarEdge.unknown);
    });

    test('every wire name round trips', () {
      for (final VerticalBarEdge value in VerticalBarEdge.values) {
        expect(VerticalBarEdge.fromWire(value.wireName), value);
      }
    });

    test('unsupported data carries no reading', () {
      expect(FoldableData.unsupported.verticalBarEdge, VerticalBarEdge.unknown);
    });

    test('takes part in equality', () {
      expect(
        dataWith(edge: VerticalBarEdge.left),
        isNot(dataWith(edge: VerticalBarEdge.right)),
      );
      expect(
        dataWith(edge: VerticalBarEdge.left)
            .copyWith(verticalBarEdge: VerticalBarEdge.right),
        dataWith(edge: VerticalBarEdge.right),
      );
    });
  });

  group('DuoMediaQuery', () {
    testWidgets('exposes the edge', (WidgetTester tester) async {
      final StreamController<FoldableData> feed =
          StreamController<FoldableData>.broadcast();
      addTearDown(feed.close);

      late VerticalBarEdge seen;
      await tester.pumpWidget(
        MaterialApp(
          home: FoldableProvider(
            debugData: feed.stream,
            child: Builder(
              builder: (BuildContext context) {
                seen = DuoMediaQuery.verticalBarEdgeOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await pushData(tester, feed, dataWith(edge: VerticalBarEdge.right));
      expect(seen, VerticalBarEdge.right);

      await pushData(tester, feed, dataWith(edge: VerticalBarEdge.left));
      expect(seen, VerticalBarEdge.left);
    });

    testWidgets('edge readers ignore a size class change and vice versa', (
      WidgetTester tester,
    ) async {
      final StreamController<FoldableData> feed =
          StreamController<FoldableData>.broadcast();
      addTearDown(feed.close);

      int edgeBuilds = 0;
      int sizeClassBuilds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: FoldableProvider(
            debugData: feed.stream,
            child: Column(
              children: <Widget>[
                Builder(
                  builder: (BuildContext context) {
                    DuoMediaQuery.verticalBarEdgeOf(context);
                    edgeBuilds++;
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

      await pushData(tester, feed, dataWith(edge: VerticalBarEdge.right));
      int edgeBaseline = edgeBuilds;
      int sizeBaseline = sizeClassBuilds;

      // Same edge, different size class.
      await pushData(
        tester,
        feed,
        dataWith(edge: VerticalBarEdge.right, horizontal: SizeClass.regular),
      );
      expect(edgeBuilds, edgeBaseline, reason: 'edge reader rebuilt');
      expect(sizeClassBuilds, greaterThan(sizeBaseline));

      edgeBaseline = edgeBuilds;
      sizeBaseline = sizeClassBuilds;

      // Same size class, different edge: moving between Split View panes.
      await pushData(
        tester,
        feed,
        dataWith(edge: VerticalBarEdge.left, horizontal: SizeClass.regular),
      );
      expect(edgeBuilds, greaterThan(edgeBaseline));
      expect(sizeClassBuilds, sizeBaseline, reason: 'size reader rebuilt');
    });

    testWidgets('without a provider returns unknown', (
      WidgetTester tester,
    ) async {
      late VerticalBarEdge seen;
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext context) {
            seen = DuoMediaQuery.verticalBarEdgeOf(context);
            return const SizedBox();
          },
        ),
      );
      expect(seen, VerticalBarEdge.unknown);
    });
  });
}
