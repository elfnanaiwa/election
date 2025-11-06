// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:activation_studio/main.dart';

void main() {
  testWidgets('Activation Studio renders main UI', (tester) async {
    await tester.pumpWidget(const ActivationStudioApp());

    // AppBar title should be visible
    expect(find.text('Activation Studio'), findsOneWidget);

    // Main hint text should be present
    expect(
      find.text(
        'Generate activation code (HMAC-SHA256): code = HMAC(secret, "serial|YYYY-MM-DD")',
      ),
      findsOneWidget,
    );

    // Form labels should be present
    expect(find.text('Machine Serial'), findsOneWidget);
    expect(find.text('Expiry (YYYY-MM-DD)'), findsOneWidget);
    expect(find.text('Secret'), findsOneWidget);
  });
}
