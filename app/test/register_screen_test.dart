import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxilife/core/theme/app_theme.dart';
import 'package:proxilife/features/auth/register_screen.dart';

import 'fakes.dart';

void main() {
  testWidgets('RIB field only appears for professional roles',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: RegisterScreen(session: makeTestSession()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('RIB (requis)'), findsNothing);

    await tester.tap(find.text('Conducteur'));
    await tester.pumpAndSettle();

    expect(find.text('RIB (requis)'), findsOneWidget);

    await tester.tap(find.text('Client'));
    await tester.pumpAndSettle();

    expect(find.text('RIB (requis)'), findsNothing);
  });
}
