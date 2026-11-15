// test/ui/values_labels_test.dart
// The learner pages' round helpers (docs/handoff/screens/value-sources.md,
// *Lists that now show the label*): they take a round as the school's
// learner-pages switch shows it (PhilIriRoundView), one kind of value only.
// Under actual a round without a reading of its own is "not assessed this
// round" (Struggling, 3 levels down); the carried-over note shows under
// carried only; no "This round alone" row next to the carried value.
import 'package:basa_capstone/core/models/phil_iri_assessment.dart';
import 'package:basa_capstone/core/models/phil_iri_types.dart';
import 'package:basa_capstone/core/models/report_setting.dart';
import 'package:basa_capstone/ui/common/screen_kit.dart';
import 'package:basa_capstone/ui/phil_iri/learner_results_screen.dart';
import 'package:basa_capstone/ui/theme/basa_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _show(WidgetTester tester, List<Widget> children) => tester.pumpWidget(MaterialApp(
      theme: basaThemeData(Brightness.light),
      home: Scaffold(body: SingleChildScrollView(child: Column(children: children))),
    ));

void main() {
  const carriedOver = PhilIriRoundView(
    round: PhilIriRound.mosy1,
    values: PhilIriValues.carried,
    wordReadingScore: 0.97,
    wordsPerMinute: 120,
    speed: PhilIriSpeed.average,
    wordReadingLevel: PhilIriLevel.instructional,
    comprehensionScore: 0.8,
    comprehensionLevel: PhilIriLevel.instructional,
    profile: PhilIriLevel.instructional,
    adjustedLevel: 7,
    levelsDown: 0,
    status: PhilIriRoundStatus.carriedOver,
  );
  const actualMissing = PhilIriRoundView(
    round: PhilIriRound.mosy1,
    values: PhilIriValues.actual,
    notAssessedThisRound: true,
    wordReadingLevel: PhilIriLevel.struggling,
    wordReadingAssumed: true,
    profile: PhilIriLevel.struggling,
    adjustedLevel: 4,
    levelsDown: 3,
    status: PhilIriRoundStatus.carriedOver,
  );

  testWidgets('carried: values and the carried-over note', (tester) async {
    await _show(tester, [roundViewChip(carriedOver), ...roundViewRows(carriedOver)]);
    expect(find.text('97% (Instructional)'), findsOneWidget);
    expect(find.text('80% (Instructional)'), findsOneWidget);
    expect(find.text('Carried from an earlier round'), findsOneWidget);
    expect(find.text('This round alone'), findsNothing);
    expect(roundViewText(carriedOver), startsWith('Instructional · '));
  });

  testWidgets('actual: a round without its own reading is not assessed this round', (tester) async {
    await _show(tester, [roundViewChip(actualMissing), ...roundViewRows(actualMissing)]);
    expect(find.text('not assessed this round'), findsOneWidget);
    expect(find.text('No reading of their own this round: counted as Struggling.'), findsOneWidget);
    expect(find.text('Level'), findsOneWidget);
    // The monitoring status is not shown under actual.
    expect(find.text('Carried from an earlier round'), findsNothing);
    expect(roundViewText(actualMissing), startsWith('not assessed this round · '));
  });

  testWidgets('actual with its own reading: no carried-over note', (tester) async {
    const own = PhilIriRoundView(
      round: PhilIriRound.mosy1,
      values: PhilIriValues.actual,
      wordReadingScore: 0.9,
      wordsPerMinute: 100,
      speed: PhilIriSpeed.average,
      wordReadingLevel: PhilIriLevel.frustration,
      comprehensionScore: 0.5,
      comprehensionLevel: PhilIriLevel.frustration,
      profile: PhilIriLevel.frustration,
      adjustedLevel: 6,
      levelsDown: 1,
      status: PhilIriRoundStatus.assessed,
    );
    await _show(tester, roundViewRows(own));
    expect(find.text('90% (Frustration)'), findsOneWidget);
    expect(find.text('Carried from an earlier round'), findsNothing);
  });

  // Owner/ma 2026-11-15: a tutor (showValues false) is never told carried or actual.
  testWidgets('tutor: a round without a reading is "No reading this round" under actual', (tester) async {
    await _show(tester, [roundViewChip(actualMissing, showValues: false), ...roundViewRows(actualMissing, showValues: false)]);
    expect(find.text('No reading this round'), findsOneWidget);
    expect(find.text('No reading this round.'), findsOneWidget);
    expect(find.textContaining('not assessed'), findsNothing);
    expect(find.textContaining('Struggling'), findsNothing);
    expect(roundViewText(actualMissing, showValues: false), 'No reading this round');
  });

  testWidgets('tutor: carried values without the carried-over note', (tester) async {
    await _show(tester, [roundViewChip(carriedOver, showValues: false), ...roundViewRows(carriedOver, showValues: false)]);
    expect(find.text('97% (Instructional)'), findsOneWidget);
    expect(find.textContaining('Carried'), findsNothing);
  });

  testWidgets('tutor: nothing all year is "No reading this round" too', (tester) async {
    const nothing = PhilIriRoundView(round: PhilIriRound.bosy, values: PhilIriValues.carried, notAssessed: true);
    expect(roundViewText(nothing, showValues: false), 'No reading this round');
    expect(roundViewText(nothing), 'not assessed');
  });

  testWidgets('ValuesNote shows the label', (tester) async {
    await _show(tester, [ValuesNote(philIriValuesLabel(PhilIriValues.actual))]);
    expect(find.text(philIriValuesLabel(PhilIriValues.actual)), findsOneWidget);
  });
}
