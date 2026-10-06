import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_salah_app/main.dart';

void main() {
  testWidgets('MySalahApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MySalahApp(initialIsDark: true));
    // Verify the app starts without errors
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
