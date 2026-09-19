import 'dart:async';


import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';

const Size kInnerDisplay = Size(626, 890);

FoldableData dataFor({
  required HingeStatus status,
  double? angle,
  bool withOcclusion = false,
}) => FoldableData(
  capabilities: const FoldableCapabilities(
    supportLevel: FoldableSupportLevel.available,
    isFoldable: true,
    hingeApiPresent: true,
    regionApiPresent: true,
    angleUnitVerified: false,
    strategy: 'test',
  ),
  status: status,
  angleDegrees: angle,
  regions: <ReservedRegion>[
    const ReservedRegion(
      kind: ReservedRegionKind.division,
      bounds: Rect.fromLTWH(293, 0, 40, 890),
      isActive: true,
    ),
    if (withOcclusion)
      const ReservedRegion(
        kind: ReservedRegionKind.occlusion,
        bounds: Rect.fromLTWH(283, 0, 60, 30),
        isActive: true,
      ),
  ],
  displayFeatures: const [],
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
  testWidgets('works without a provider and reports FoldInfo.none', (
    WidgetTester tester,
  ) async {
    late FoldInfo seen;
    await tester.pumpWidget(
      MaterialApp(
        home: FoldAwareBuilder(
          builder: (BuildContext context, BoxConstraints c, FoldInfo fold) {
            seen = fold;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    expect(seen, FoldInfo.none);
    expect(seen.isFoldable, isFalse);
    expect(seen.spansDivision, isFalse);
  });

  testWidgets('exposes posture and fold geometry', (WidgetTester tester) async {
    final StreamController<FoldableData> feed =
        StreamController<FoldableData>.broadcast();
    addTearDown(feed.close);

    late FoldInfo seen;
    await tester.pumpWidget(
      MaterialApp(
        home: FoldableProvider(
          debugData: feed.stream,
          child: FoldAwareBuilder(
            builder: (BuildContext context, BoxConstraints c, FoldInfo fold) {
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
      dataFor(status: HingeStatus.partiallyOpen, angle: 97, withOcclusion: true),
    );

    expect(seen.isFoldable, isTrue);
    expect(seen.isPartiallyOpen, isTrue);
    expect(seen.isFullyOpen, isFalse);
    expect(seen.angleDegrees, 97);
    expect(seen.divisionRects, hasLength(1));
    expect(seen.occlusionRects, hasLength(1));
    expect(seen.spansDivision, isTrue);
    expect(seen.divisionRect, isNotNull);
  });

  testWidgets('ignores a division that still claims to be active when flat', (
    WidgetTester tester,
  ) async {
    // The region's isActive flag lags the hinge: just after the device is laid
    // flat it still reads true. The posture wins, so no two-pane layout sticks.
    final StreamController<FoldableData> feed =
        StreamController<FoldableData>.broadcast();
    addTearDown(feed.close);

    late FoldInfo seen;
    await tester.pumpWidget(
      MaterialApp(
        home: FoldableProvider(
          debugData: feed.stream,
          child: FoldAwareBuilder(
            builder: (BuildContext context, BoxConstraints c, FoldInfo fold) {
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
      dataFor(status: HingeStatus.fullyOpen, angle: 180),
    );

    expect(seen.isFullyOpen, isTrue);
    expect(seen.divisionRects, isEmpty);
    expect(seen.spansDivision, isFalse);
  });

  testWidgets('rebuilds on posture change', (WidgetTester tester) async {
    final StreamController<FoldableData> feed =
        StreamController<FoldableData>.broadcast();
    addTearDown(feed.close);

    final List<HingeStatus> seen = <HingeStatus>[];
    await tester.pumpWidget(
      MaterialApp(
        home: FoldableProvider(
          debugData: feed.stream,
          child: FoldAwareBuilder(
            builder: (BuildContext context, BoxConstraints c, FoldInfo fold) {
              seen.add(fold.status);
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    await pushData(
      tester,
      feed,
      dataFor(status: HingeStatus.partiallyOpen, angle: 90),
    );
    await pushData(
      tester,
      feed,
      dataFor(status: HingeStatus.fullyOpen, angle: 180),
    );

    expect(seen, contains(HingeStatus.partiallyOpen));
    expect(seen.last, HingeStatus.fullyOpen);
  });

  testWidgets('provides layout constraints alongside fold state', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = kInnerDisplay * 3.0;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    late BoxConstraints seen;
    await tester.pumpWidget(
      MaterialApp(
        home: FoldAwareBuilder(
          builder: (BuildContext context, BoxConstraints c, FoldInfo fold) {
            seen = c;
            return const SizedBox.expand();
          },
        ),
      ),
    );

    expect(seen.maxWidth, kInnerDisplay.width);
    expect(seen.maxHeight, kInnerDisplay.height);
  });

  group('FoldInfo', () {
    test('value equality holds across identical instances', () {
      const FoldInfo a = FoldInfo(
        isFoldable: true,
        status: HingeStatus.partiallyOpen,
        angleDegrees: 90,
        divisionRects: <Rect>[Rect.fromLTWH(0, 0, 10, 10)],
        occlusionRects: <Rect>[],
      );
      const FoldInfo b = FoldInfo(
        isFoldable: true,
        status: HingeStatus.partiallyOpen,
        angleDegrees: 90,
        divisionRects: <Rect>[Rect.fromLTWH(0, 0, 10, 10)],
        occlusionRects: <Rect>[],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('none reports no fold', () {
      expect(FoldInfo.none.isFoldable, isFalse);
      expect(FoldInfo.none.spansDivision, isFalse);
      expect(FoldInfo.none.divisionRect, isNull);
      expect(FoldInfo.none.isClosed, isFalse);
    });
  });
}
