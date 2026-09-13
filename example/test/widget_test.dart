import 'package:flutter_test/flutter_test.dart';

import 'package:foldable_example/main.dart';

void main() {
  testWidgets('example app builds and shows the device card', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const FoldableExampleApp());
    await tester.pump();

    expect(find.text('Device'), findsOneWidget);
    expect(find.text('Hinge angle'), findsOneWidget);
  });
}
