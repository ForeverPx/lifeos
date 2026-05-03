// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:lifeos/main.dart';

void main() {
  testWidgets('LifeOS home smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const LifeOSApp());
    // Avoid `pumpAndSettle`: async work and overlays can prevent settling.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Shell always shows bottom nav; home title may be loading or token hint.
    expect(find.text('首页'), findsOneWidget);
  });
}
