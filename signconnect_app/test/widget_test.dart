// This is a basic Flutter widget smoke test.
//
// Widgets can be interacted with using the WidgetTester utility in the
// flutter_test package, e.g. send tap/scroll gestures or read text values.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:signconnect_app/main.dart';
import 'package:signconnect_app/screens/auth/login_screen.dart';

void main() {
  testWidgets('SignConnectApp renders login screen smoke test',
      (WidgetTester tester) async {
    await tester.pumpWidget(const SignConnectApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
