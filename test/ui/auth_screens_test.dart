// test/ui/auth_screens_test.dart
// The offline sign-in status card (ready / window passed / no attempts left /
// none saved) and its date format.
import 'package:basa_capstone/core/models/offline_status.dart';
import 'package:basa_capstone/ui/auth/sign_in_offline_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

OfflineStatus _status({required DateTime until, int failed = 0}) => OfflineStatus(
  email: 'tutor@school.ph',
  lastOnlineAt: until.subtract(const Duration(days: 14)).toUtc().toIso8601String(),
  windowDays: 14,
  until: until,
  failedAttempts: failed,
  maxFailedAttempts: 5,
);

Future<void> _pump(WidgetTester tester, OfflineStatus? s) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: OfflineStatusCard(status: s))));

void main() {
  test('formatDate', () {
    expect(formatDate(DateTime(2026, 10, 7, 9, 5)), '7 Oct 2026, 09:05');
  });

  testWidgets('none saved', (tester) async {
    await _pump(tester, null);
    expect(find.text('Offline sign-in is not set up on this device'), findsOneWidget);
  });

  testWidgets('ready, with attempts left', (tester) async {
    await _pump(tester, _status(until: DateTime.now().add(const Duration(days: 3)), failed: 2));
    expect(find.text('Offline sign-in ready'), findsOneWidget);
    expect(find.text('For tutor@school.ph'), findsOneWidget);
    expect(find.text('3 of 5 attempts left'), findsOneWidget);
  });

  testWidgets('window passed', (tester) async {
    await _pump(tester, _status(until: DateTime.now().subtract(const Duration(days: 1))));
    expect(find.text('Offline window has passed'), findsOneWidget);
  });

  testWidgets('no attempts left', (tester) async {
    await _pump(tester, _status(until: DateTime.now().add(const Duration(days: 3)), failed: 5));
    expect(find.text('Too many wrong passwords'), findsOneWidget);
    expect(find.text('0 of 5 attempts left'), findsOneWidget);
  });
}
