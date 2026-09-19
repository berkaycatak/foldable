import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';

FoldableData dataFor(HingeStatus status) => FoldableData(
  capabilities: const FoldableCapabilities(
    supportLevel: FoldableSupportLevel.available,
    isFoldable: true,
    hingeApiPresent: true,
    regionApiPresent: true,
    angleUnitVerified: true,
    strategy: 'test',
  ),
  status: status,
  angleDegrees: status == HingeStatus.fullyOpen ? 180 : 95,
  regions: const <ReservedRegion>[
    ReservedRegion(
      kind: ReservedRegionKind.division,
      bounds: Rect.fromLTWH(455.5, 0, 40, 669),
      isActive: true,
    ),
  ],
  displayFeatures: const [],
);

class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  static int initCount = 0;

  @override
  void initState() {
    super.initState();
    initCount++;
  }

  @override
  Widget build(BuildContext context) =>
      Text('${MediaQuery.of(context).displayFeatures.length}');
}

void main() {
  testWidgets('publishing and withdrawing a fold keeps the subtree mounted', (
    WidgetTester tester,
  ) async {
    // The provider used to insert a MediaQuery only while it had features to
    // publish. That changed the shape of the tree, so every fold and unfold in
    // `full` mode, and every change of bridge mode, rebuilt the whole app below
    // it from scratch: scroll positions, text fields and State were lost.
    _ProbeState.initCount = 0;
    final StreamController<FoldableData> feed =
        StreamController<FoldableData>.broadcast();
    addTearDown(feed.close);

    Future<void> pump(DisplayFeatureBridgeMode mode) => tester.pumpWidget(
      MaterialApp(
        home: FoldableProvider(
          bridgeMode: mode,
          debugData: feed.stream,
          child: const _Probe(),
        ),
      ),
    );

    Future<void> push(HingeStatus status) async {
      feed.add(dataFor(status));
      await tester.pump();
      await tester.pump();
    }

    await pump(DisplayFeatureBridgeMode.full);
    await push(HingeStatus.fullyOpen);
    expect(find.text('0'), findsOneWidget);

    await push(HingeStatus.partiallyOpen);
    expect(find.text('1'), findsOneWidget);

    await push(HingeStatus.fullyOpen);
    expect(find.text('0'), findsOneWidget);

    await pump(DisplayFeatureBridgeMode.none);
    await push(HingeStatus.partiallyOpen);
    expect(find.text('0'), findsOneWidget);

    await pump(DisplayFeatureBridgeMode.full);
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    expect(_ProbeState.initCount, 1);
  });
}
