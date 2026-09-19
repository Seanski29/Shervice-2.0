import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shervice_flutter/session_manager.dart';
import 'package:shervice_flutter/theme/theme_manager.dart';
import 'package:shervice_flutter/widgets/shared/enterprise_data_grid.dart';

void main() {
  testWidgets('enterprise grid exposes spreadsheet controls and navigation', (
    tester,
  ) async {
    final rows = [
      {'id': '1', 'name': 'Alpha', 'status': 'Active'},
      {'id': '2', 'name': 'Bravo', 'status': 'Inactive'},
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EnterpriseDataGrid<Map<String, String>>(
            rows: rows,
            rowKey: (row) => row['id']!,
            columns: [
              EnterpriseGridColumn(label: 'Name', value: (row) => row['name']!),
              EnterpriseGridColumn(
                label: 'Status',
                value: (row) => row['status']!,
              ),
            ],
            emptyTitle: 'No records in this register',
            emptyMessage: 'Create the first record to begin.',
            emptyActionLabel: 'Create record',
            onEmptyAction: () {},
          ),
        ),
      ),
    );

    expect(find.text('100%'), findsOneWidget);
    expect(find.text('Date range'), findsOneWidget);
    expect(
      find.text('Arrow keys move cells | Tab advances | F2 edits'),
      findsOneWidget,
    );
    expect(find.text('Alpha'), findsOneWidget);

    await tester.tap(find.text('Alpha'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('theme preference is scoped to the signed-in account', () async {
    SharedPreferences.setMockInitialValues({
      'isLoggedIn': true,
      'role': 'admin',
    });

    await ThemeManager.loadSavedTheme(userId: 'admin-1');
    await ThemeManager.setDarkMode(false);
    expect(ThemeManager.themeMode, ThemeMode.light);

    await ThemeManager.loadSavedTheme(userId: 'staff-1');
    expect(ThemeManager.themeMode, ThemeMode.dark);
    await ThemeManager.setDarkMode(true);

    await ThemeManager.loadSavedTheme(userId: 'admin-1');
    expect(ThemeManager.themeMode, ThemeMode.light);

    await SessionManager.clearSession();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('theme.darkMode.account.admin-1'), isFalse);
    expect(prefs.getBool('theme.darkMode.account.staff-1'), isTrue);
    expect(prefs.getBool('isLoggedIn'), isNull);
  });

  test('legacy theme preference migrates to only the active account', () async {
    SharedPreferences.setMockInitialValues({'darkMode': false});

    await ThemeManager.loadSavedTheme(userId: 'admin-1');
    expect(ThemeManager.themeMode, ThemeMode.light);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('theme.darkMode.account.admin-1'), isFalse);
    expect(prefs.containsKey('darkMode'), isFalse);

    await ThemeManager.loadSavedTheme(userId: 'staff-1');
    expect(ThemeManager.themeMode, ThemeMode.dark);
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
