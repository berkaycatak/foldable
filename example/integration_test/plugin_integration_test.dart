import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';
import 'package:integration_test/integration_test.dart';

/// Runs on a real simulator or device.
///
/// The assertions branch on what the platform reports rather than on a device
/// name: on an iPhone Duo the hinge APIs resolve and a real angle arrives, and
/// on anything else the package has to degrade cleanly instead of hanging.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capabilities are internally consistent', (tester) async {
    final FoldableCapabilities caps = await Foldable.capabilities;

    if (caps.hingeApiPresent) {
      // iOS 27.1 or newer: the symbols resolved.
      expect(caps.strategy, isNot('none'));
      expect(
        caps.supportLevel,
        anyOf(
          FoldableSupportLevel.available,
          FoldableSupportLevel.availableNoHinge,
          FoldableSupportLevel.unknown,
        ),
      );
    } else {
      expect(caps.supportLevel, FoldableSupportLevel.unsupported);
      expect(caps.isFoldable, isFalse);
    }
  });

  testWidgets('size classes come back from the real trait collection', (
    tester,
  ) async {
    final FoldableData data = await Foldable.snapshot;
    expect(
      data.horizontalSizeClass,
      anyOf(SizeClass.compact, SizeClass.regular),
    );
    expect(data.verticalSizeClass, anyOf(SizeClass.compact, SizeClass.regular));
  });

  testWidgets('hinge resolves to a settled answer', (tester) async {
    // The platform reports the absence of a hinge through an update, so the
    // first snapshot can legitimately be "unknown". Give it a moment.
    FoldableData data = await Foldable.snapshot;
    for (int i = 0; i < 20 && !data.isFoldable; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      data = await Foldable.snapshot;
    }

    if (data.isFoldable) {
      // A foldable device must report a real posture and a real angle.
      expect(data.status, isNot(HingeStatus.unknown));
      expect(data.angleDegrees, isNotNull);
      expect(data.angleDegrees, inInclusiveRange(0.0, 180.0));
      expect(data.capabilities.angleUnitVerified, isTrue);
      // ignore: avoid_print
      print('DUO: status=${data.status.name} '
          'angle=${data.angleDegrees!.toStringAsFixed(1)} '
          'strategy=${data.capabilities.strategy} '
          'regions=${data.regions.length} '
          'sizeClass=${data.horizontalSizeClass.name}');
      for (final ReservedRegion r in data.regions) {
        // ignore: avoid_print
        print('  region ${r.kind.name} active=${r.isActive} ${r.bounds}');
      }
    } else {
      // No hinge: the streams must complete instead of hanging.
      await expectLater(
        Foldable.hingeAngleStream.toList(),
        completion(isEmpty),
      );
    }
  });

  testWidgets('native API dump reflects the running OS', (tester) async {
    final Map<String, Object?> dump = await Foldable.debugDumpNativeApi();
    // ignore: avoid_print
    print('DUMP hingeApi=${dump['hingeApiPresent']} '
        'regionApi=${dump['regionApiPresent']} '
        'native=${dump['builtWithNativeApi']} '
        'os=${dump['systemVersion']}');
    expect(dump['classes'], isA<Map<Object?, Object?>>());
  });
}
