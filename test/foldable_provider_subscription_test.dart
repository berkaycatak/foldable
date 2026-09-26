import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:foldable/foldable.dart';

// Regression test for issue #2: the provider must keep listening when the
// first snapshot has not settled yet.

Map<String, Object?> snapshot(
        {required bool settled, String status = 'unknown'}) =>
    <String, Object?>{
      'wireVersion': 1,
      'supportLevel': settled ? 'available' : 'unknown',
      'isFoldable': settled,
      'hingeApiPresent': true,
      'regionApiPresent': true,
      'angleUnitVerified': true,
      'strategy': 'test',
      'status': status,
      'angleDegrees': status == 'partiallyOpen' ? 95.0 : null,
      'regions': <Object?>[
        <String, Object?>{
          'kind': 'division',
          'active': status == 'partiallyOpen',
          'left': 455.5,
          'top': 0.0,
          'width': 40.0,
          'height': 669.0,
        },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  MockStreamHandlerEventSink? sink;

  setUp(() {
    sink = null;
    FoldablePlatform.instance = MethodChannelFoldable();
    messenger
      ..setMockMethodCallHandler(
        const MethodChannel('foldable/methods'),
        (_) async => snapshot(settled: false),
      )
      ..setMockStreamHandler(
        const EventChannel('foldable/events'),
        MockStreamHandler.inline(onListen: (_, MockStreamHandlerEventSink s) {
          sink = s;
        }),
      );
  });

  tearDown(() {
    messenger
      ..setMockMethodCallHandler(const MethodChannel('foldable/methods'), null)
      ..setMockStreamHandler(const EventChannel('foldable/events'), null);
  });

  testWidgets(
    'half-open after an initial "unknown" snapshot reaches displayFeatures',
    (WidgetTester tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        FoldableProvider(
          bridgeMode: DisplayFeatureBridgeMode.full,
          child: Builder(
            builder: (BuildContext c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      Future<void> settle() async {
        for (int i = 0; i < 3; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
      }

      await settle();
      expect(sink, isNotNull,
          reason: 'provider should listen to foldable/events');
      sink!.success(snapshot(settled: true, status: 'partiallyOpen'));
      await settle();
      expect(MediaQuery.of(ctx).displayFeatures, isNotEmpty);
    },
  );
}
