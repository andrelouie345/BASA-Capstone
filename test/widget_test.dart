// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:basa_capstone/features/dashboard/screens/dashboard_screen.dart';
import 'package:basa_capstone/features/dashboard/widgets/basa_sidebar.dart';
import 'package:basa_capstone/features/assessments/screens/assessments_screen.dart';
import 'package:basa_capstone/main.dart';

void main() {
  testWidgets('BASA login screen renders core content', (WidgetTester tester) async {
    await tester.pumpWidget(const BasaApp());

    expect(find.text('BASA'), findsWidgets);
    expect(find.text('Sign in to BASA'), findsOneWidget);
    expect(find.text('SIGN IN AS'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('Dashboard learners view reuses the existing shell without duplicating sidebar', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await tester.pumpWidget(
      const MaterialApp(
        home: DashboardScreen(initialRoute: '/learners'),
      ),
    );

    expect(find.byType(BasaSidebar), findsOneWidget);
    expect(find.text('BASA > Learner Profiles'), findsOneWidget);
  });

  testWidgets('Reading Assessments screen renders and supports GST inputs', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AssessmentsScreen(),
        ),
      ),
    );

    expect(find.text('Reading Assessments'), findsOneWidget);
    expect(find.text('Group Screening (GST)'), findsOneWidget);
    expect(find.text('CRLA'), findsOneWidget);
    expect(find.text('Phil-IRI'), findsOneWidget);
    expect(find.text('Assessment Records'), findsOneWidget);

    // Verify default GST content
    expect(find.text('Administer Group Screening Test'), findsOneWidget);
    expect(find.text('Maria Elena Santos'), findsOneWidget);
  });

  testWidgets('Reading Assessments CRLA and Phil-IRI sub-pages render high fidelity controls', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AssessmentsScreen(initialTab: 'CRLA'),
        ),
      ),
    );

    // Verify CRLA specific layout elements
    expect(find.text('Administer CRLA Assessment'), findsOneWidget);
    expect(find.text('5 ASSESSMENT AREAS'), findsOneWidget);
    expect(find.text('Letter Identification'), findsWidgets);
    expect(find.text('Phonemic Awareness'), findsWidgets);

    // Switch tab to Phil-IRI
    await tester.tap(find.text('Phil-IRI'));
    await tester.pumpAndSettle();

    // Verify Phil-IRI specific layout elements
    expect(find.text('Phil-IRI Diagnostic Session'), findsOneWidget);
    expect(find.text('LIVE SESSION CONTROLS'), findsOneWidget);
    expect(find.text('PASSAGE SCORES — MANUAL ENTRY'), findsOneWidget);
    expect(find.text('Pre-Primer'), findsWidgets);
    expect(find.text('Primer'), findsWidgets); // near top of passage list, always rendered
  });
}
