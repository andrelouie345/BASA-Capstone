// test/ui/search_widgets_test.dart
// Long lists get a search box: BasaDropdown and pickOne stay plain up to
// kSearchableThreshold items and filter on any part of the label above it.
import 'package:basa_capstone/ui/common/pickers.dart';
import 'package:basa_capstone/ui/common/screen_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Item {
  final int id;
  final String name;
  _Item(this.id, this.name);
}

final _long = [
  _Item(1, 'Dela Cruz, Juan · 123456789012'),
  _Item(2, 'Santos, Maria · 223456789012'),
  _Item(3, 'Reyes, Jose · 323456789012'),
  _Item(4, 'Garcia, Ana · 423456789012'),
  _Item(5, 'Bautista, Pedro · 523456789012'),
  _Item(6, 'Mendoza, Liza · 623456789012'),
  _Item(7, 'De la Rosa, Carlo · 723456789012'),
];

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)));

void main() {
  test('matchesSearch ignores case and matches any part', () {
    expect(matchesSearch('', ['x']), isTrue);
    expect(matchesSearch('DELA', ['Dela Cruz, Juan']), isTrue);
    expect(matchesSearch('6789', [null, '123456789012']), isTrue);
    expect(matchesSearch('zz', ['Dela Cruz']), isFalse);
  });

  testWidgets('a short BasaDropdown stays a plain dropdown', (tester) async {
    await tester.pumpWidget(_host(BasaDropdown<_Item>(
      label: 'Learner',
      items: _long.take(kSearchableThreshold).toList(),
      value: null,
      itemLabel: (i) => i.name,
      onChanged: (_) {},
    )));
    expect(find.byType(DropdownButtonFormField<_Item>), findsOneWidget);
    expect(find.byType(DropdownMenu<_Item?>), findsNothing);
  });

  testWidgets('a long BasaDropdown filters, shows No matches, and keeps the choice', (tester) async {
    _Item? chosen = _long[1];
    await tester.pumpWidget(_host(StatefulBuilder(
      builder: (context, setState) => BasaDropdown<_Item>(
        label: 'Learner',
        items: _long,
        value: chosen,
        itemLabel: (i) => i.name,
        onChanged: (v) => setState(() => chosen = v),
      ),
    )));
    expect(find.byType(DropdownMenu<_Item?>), findsOneWidget);
    final field = find.byType(TextField);
    expect(tester.widget<TextField>(field).controller!.text, _long[1].name);

    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'dela');
    await tester.pumpAndSettle();
    expect(find.text(_long[0].name), findsWidgets);
    expect(find.text(_long[3].name), findsNothing);
    expect(chosen, same(_long[1]), reason: 'typing does not change the choice');

    await tester.enterText(field, 'nobody');
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);

    await tester.enterText(field, '7234');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(chosen, same(_long[6]));
  });

  testWidgets('keyboard: arrow keys and Enter pick, Enter with no match keeps the choice', (tester) async {
    _Item? chosen = _long[1];
    await tester.pumpWidget(_host(StatefulBuilder(
      builder: (context, setState) => BasaDropdown<_Item>(
        label: 'Learner',
        items: _long,
        value: chosen,
        itemLabel: (i) => i.name,
        onChanged: (v) => setState(() => chosen = v),
      ),
    )));
    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, 'nobody');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done); // Enter
    await tester.pumpAndSettle();
    expect(chosen, same(_long[1]));

    await tester.enterText(field, 'de');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done); // Enter
    await tester.pumpAndSettle();
    expect(chosen, same(_long[6]), reason: 'second match of "de" (Dela Cruz, De la Rosa)');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('pickOne search dialog: arrow keys and Enter pick on Windows', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_host(Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    final picked = pickOne<_Item>(ctx, title: 'Long', options: _long, label: (i) => i.name);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'de');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.testTextInput.receiveAction(TextInputAction.done); // Enter
    await tester.pumpAndSettle();
    expect(await picked, same(_long[6]), reason: 'second match of "de" (Dela Cruz, De la Rosa)');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a value no longer in the list shows nothing chosen', (tester) async {
    await tester.pumpWidget(_host(BasaDropdown<_Item>(
      label: 'Learner',
      items: _long,
      value: _Item(99, 'Gone'),
      itemLabel: (i) => i.name,
      onChanged: (_) {},
    )));
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
  });

  testWidgets('pickOne: plain up to the threshold, searchable above it', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_host(Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));

    pickOne<_Item>(ctx, title: 'Short', options: _long.take(3).toList(), label: (i) => i.name);
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    Navigator.of(ctx).pop();
    await tester.pumpAndSettle();

    final picked = pickOne<_Item>(ctx, title: 'Long', options: _long, label: (i) => i.name);
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsNothing);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text(_long[0].name), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'santos');
    await tester.pumpAndSettle();
    await tester.tap(find.text(_long[1].name));
    await tester.pumpAndSettle();
    expect(await picked, same(_long[1]));
  });

  testWidgets('pickOne: searchable false keeps a long action menu plain', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_host(Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    pickOne<_Item>(ctx, title: 'Actions', options: _long, label: (i) => i.name, searchable: false);
    await tester.pumpAndSettle();
    expect(find.byType(SimpleDialog), findsOneWidget);
  });
}
