import 'dart:async';
import 'dart:ui' show DisplayFeature, Rect;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';

const Size kInnerDisplay = Size(626, 890);

FoldableData dataFor({
  required HingeStatus status,
  double? angle,
  bool divisionActive = true,
  double thickness = 40,
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
    ReservedRegion(
      kind: ReservedRegionKind.division,
      bounds: Rect.fromLTWH(
        (kInnerDisplay.width - thickness) / 2,
        0,
        thickness,
        kInnerDisplay.height,
      ),
      isActive: divisionActive,
    ),
  ],
  displayFeatures: const [],
);

/// Pushes a snapshot and lets the resulting setState reach a build.
///
/// A stream event delivered mid-frame lands after that frame's build phase,
/// so a single pump is not enough to observe it.
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
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  group('bridgeMode: none (default)', () {
    testWidgets('leaves MediaQuery.displayFeatures untouched', (
      WidgetTester tester,
    ) async {
      final StreamController<FoldableData> feed =
          StreamController<FoldableData>.broadcast();
      addTearDown(feed.close);

      late List<DisplayFeature> observed;
      await tester.pumpWidget(
        MaterialApp(
          home: FoldableProvider(
            debugData: feed.stream,
            child: Builder(
              builder: (BuildContext context) {
                observed = MediaQuery.of(context).displayFeatures;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await pushData(tester, feed, dataFor(status: HingeStatus.partiallyOpen, angle: 95));

      expect(observed, isEmpty);
    });

    testWidgets('AlertDialog keeps the width it has without the package', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = kInnerDisplay * 3.0;
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      Future<double> dialogWidth({required bool withProvider}) async {
        final StreamController<FoldableData> feed =
            StreamController<FoldableData>.broadcast();
        addTearDown(feed.close);

        Widget body = Builder(
          builder: (BuildContext context) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const AlertDialog(content: Text('x')),
            ),
            child: const Text('open'),
          ),
        );
        if (withProvider) {
          body = FoldableProvider(debugData: feed.stream, child: body);
        }

        await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
        if (withProvider) {
          await pushData(tester, feed, dataFor(status: HingeStatus.partiallyOpen, angle: 95));
        }
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        final double width = tester.getSize(find.byType(AlertDialog)).width;
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        return width;
      }

      final double without = await dialogWidth(withProvider: false);
      final double with_ = await dialogWidth(withProvider: true);

      // The harmlessness contract: adding this package must not change a
      // single Material surface while bridging is off.
      expect(with_, without);
    });
  });

  group('bridgeMode: full', () {
    testWidgets('publishes the fold and the framework acts on it', (
      WidgetTester tester,
    ) async {
      final StreamController<FoldableData> feed =
          StreamController<FoldableData>.broadcast();
      addTearDown(feed.close);

      late MediaQueryData observed;
      await tester.pumpWidget(
        MaterialApp(
          home: FoldableProvider(
            bridgeMode: DisplayFeatureBridgeMode.full,
            debugData: feed.stream,
            child: Builder(
              builder: (BuildContext context) {
                observed = MediaQuery.of(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await pushData(tester, feed, dataFor(status: HingeStatus.partiallyOpen, angle: 95));

      expect(observed.displayFeatures, hasLength(1));
      expect(DisplayFeatureSubScreen.avoidBounds(observed), hasLength(1));
    });

    testWidgets('inactive division publishes nothing', (
      WidgetTester tester,
    ) async {
      final StreamController<FoldableData> feed =
          StreamController<FoldableData>.broadcast();
      addTearDown(feed.close);

      late List<DisplayFeature> observed;
      await tester.pumpWidget(
        MaterialApp(
          home: FoldableProvider(
            bridgeMode: DisplayFeatureBridgeMode.full,
            debugData: feed.stream,
            child: Builder(
              builder: (BuildContext context) {
                observed = MediaQuery.of(context).displayFeatures;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await pushData(tester, feed, dataFor(status: HingeStatus.fullyOpen, divisionActive: false));

      expect(observed, isEmpty);
    });
  });

  group('aspect-scoped rebuilds', () {
    testWidgets('angle changes below threshold do not rebuild status readers', (
      WidgetTester tester,
    ) async {
      final StreamController<FoldableData> feed =
          StreamController<FoldableData>.broadcast();
      addTearDown(feed.close);

      int statusBuilds = 0;
      int angleBuilds = 0;

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
                    DuoMediaQuery.angleOf(context);
                    angleBuilds++;
                    return const SizedBox();
                  },
                ),
              ],
            ),
          ),
        ),
      );

      await pushData(tester, feed, dataFor(status: HingeStatus.partiallyOpen, angle: 90));
      final int statusAfterFirst = statusBuilds;
      final int angleAfterFirst = angleBuilds;

      // A large angle sweep at a constant posture.
      await pushData(tester, feed, dataFor(status: HingeStatus.partiallyOpen, angle: 120));

      expect(
        statusBuilds,
        statusAfterFirst,
        reason: 'posture reader rebuilt on an angle-only change',
      );
      expect(angleBuilds, greaterThan(angleAfterFirst));
    });

    testWidgets('sub-threshold angle jitter rebuilds nothing', (
      WidgetTester tester,
    ) async {
      final StreamController<FoldableData> feed =
          StreamController<FoldableData>.broadcast();
      addTearDown(feed.close);

      int angleBuilds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: FoldableProvider(
            debugData: feed.stream,
            child: Builder(
              builder: (BuildContext context) {
                DuoMediaQuery.angleOf(context);
                angleBuilds++;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await pushData(tester, feed, dataFor(status: HingeStatus.partiallyOpen, angle: 90.0));
      final int baseline = angleBuilds;

      await pushData(tester, feed, dataFor(status: HingeStatus.partiallyOpen, angle: 90.2));

      expect(angleBuilds, baseline);
    });
  });

  group('without a provider', () {
    testWidgets('of() returns unsupported instead of throwing', (
      WidgetTester tester,
    ) async {
      late FoldableData data;
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext context) {
            data = DuoMediaQuery.of(context);
            return const SizedBox();
          },
        ),
      );
      expect(data, FoldableData.unsupported);
      expect(data.isFoldable, isFalse);
    });
  });
}
