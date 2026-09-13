import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';
import 'package:integration_test/integration_test.dart';

/// Runs on a real simulator or device.
///
/// On any hardware without a hinge, which today is all of it, these assert
/// the path every user of this package currently takes: the plugin registers,
/// reports no fold, and closes its stream cleanly instead of hanging.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reports a non-foldable device without throwing', (
    WidgetTester tester,
  ) async {
    expect(await Foldable.isFoldable, isFalse);
  });

  testWidgets('capabilities describe why support is absent', (
    WidgetTester tester,
  ) async {
    final FoldableCapabilities caps = await Foldable.capabilities;
    expect(caps.isFoldable, isFalse);
    // Xcode 26 SDKs have no hinge symbols at all, so nothing resolves.
    expect(caps.supportLevel, FoldableSupportLevel.unsupported);
    expect(caps.hingeApiPresent, isFalse);
    expect(caps.strategy, 'none');
  });

  testWidgets('hinge status reads as unknown', (WidgetTester tester) async {
    expect(await Foldable.hingeStatus, HingeStatus.unknown);
  });

  testWidgets('angle stream completes without emitting', (
    WidgetTester tester,
  ) async {
    // The empty-stream contract: a clean onDone, never a hang.
    await expectLater(Foldable.hingeAngleStream.toList(), completion(isEmpty));
  });

  testWidgets('size classes come back from the real trait collection', (
    WidgetTester tester,
  ) async {
    final FoldableData data = await Foldable.snapshot;
    // Size classes exist on every iOS device, unlike the hinge. On an iPhone
    // in portrait UIKit reports compact width and regular height.
    expect(data.horizontalSizeClass, SizeClass.compact);
    expect(data.verticalSizeClass, SizeClass.regular);
  });

  testWidgets('native API dump runs and reports no hinge classes', (
    WidgetTester tester,
  ) async {
    final Map<String, Object?> dump = await Foldable.debugDumpNativeApi();
    expect(dump['hingeApiPresent'], isFalse);
    expect(dump['builtWithNativeApi'], isFalse);
    expect(dump['classes'], isA<Map<Object?, Object?>>());
  });
}
