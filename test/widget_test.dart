import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aquatrack/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('tracks and undoes cups locally', (WidgetTester tester) async {
    await tester.pumpWidget(const AquaTrackApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    expect(find.text('0 / 8 cups'), findsOneWidget);

    await tester.tap(find.text('I drank a cup'));
    await tester.pumpAndSettle();

    expect(find.text('1 / 8 cups'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.text('0 / 8 cups'), findsOneWidget);
  });

  testWidgets('updates the daily goal in settings',
      (WidgetTester tester) async {
    await tester.pumpWidget(const AquaTrackApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ListTile, 'Daily Goal'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '10');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('10 cups per day'), findsOneWidget);
  });
}
