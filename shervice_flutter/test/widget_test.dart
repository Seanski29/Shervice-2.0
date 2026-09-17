import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Make sure this points to your active Admin wrapper or SharedReportsManager
import 'package:shervice_flutter/screens/admin/admin_reports_manager.dart';
import 'package:shervice_flutter/session_manager.dart';
import 'package:shervice_flutter/theme/theme_manager.dart';

void main() {
  testWidgets('admin reports screen enables import only on timecard tab', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AdminReportsManager()));

    expect(find.text('Import & Export'), findsOneWidget);
    expect(find.text('Trips'), findsOneWidget);
    expect(find.text('Maintenance'), findsOneWidget);
    expect(find.text('Timecard'), findsOneWidget);

    // Verify Attendance was completely removed
    expect(find.text('Attendance'), findsNothing);

    // 1. Timecard is now the default, so the button should be active immediately
    final timecardImportButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Import Excel'),
    );
    expect(timecardImportButton.onPressed, isNotNull);

    // 2. Tap 'Trips' to verify the button correctly locks itself
    await tester.tap(find.text('Trips'));
    await tester.pump();

    final lockedImportButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Import Locked'),
    );
    expect(lockedImportButton.onPressed, isNull);
  });

  test('theme preference survives loading and logout', () async {
    SharedPreferences.setMockInitialValues({
      'darkMode': true,
      'isLoggedIn': true,
      'role': 'admin',
    });

    await ThemeManager.loadSavedTheme();
    expect(ThemeManager.themeMode, ThemeMode.dark);

    await SessionManager.clearSession();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('darkMode'), isTrue);
    expect(prefs.getBool('isLoggedIn'), isNull);
  });

  test('session expires after one week', () async {
    SharedPreferences.setMockInitialValues({
      'isLoggedIn': true,
      'sessionCreatedAt': DateTime.now()
          .subtract(const Duration(days: 7))
          .millisecondsSinceEpoch,
    });

    expect(await SessionManager.isLoggedIn(), isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('isLoggedIn'), isNull);
    expect(prefs.getInt('sessionCreatedAt'), isNull);
  });
}
