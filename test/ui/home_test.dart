// test/ui/home_test.dart
// The home screen's navigation lists (both builds), the greeting, and the
// screen an entry opens while its own screen isn't built.
import 'package:basa_capstone/ui/admin/admin_home_sections.dart';
import 'package:basa_capstone/ui/home/home_screen.dart';
import 'package:basa_capstone/ui/home/home_sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Iterable<HomeEntry> _entries(List<HomeSection> sections) => sections.expand((s) => s.groups).expand((g) => g.entries);

void main() {
  group('sections', () {
    test('tutor build: Home first, at most five (bottom bar), ids unique', () {
      final sections = basaHomeSections();
      expect(sections.first.id, HomeSectionIds.home);
      expect(sections.length, lessThanOrEqualTo(5));
      expect(sections.map((s) => s.id).toSet().length, sections.length);
    });

    test('admin build keeps every shared entry and adds its own', () {
      final shared = _entries(basaHomeSections()).map((e) => e.checklistRow).toSet();
      final admin = _entries(adminHomeSections()).map((e) => e.checklistRow).toSet();
      expect(admin.containsAll(shared), isTrue);
      expect(admin.difference(shared), containsAll([12, 13, 17, 18, 19, 26, 31, 43, 44, 45, 46, 48, 49, 56]));
    });

    test('each checklist row appears once per build', () {
      for (final sections in [basaHomeSections(), adminHomeSections()]) {
        final rows = _entries(sections).map((e) => e.checklistRow).toList();
        expect(rows.toSet().length, rows.length);
      }
    });

    test('adding() appends to a named group, or adds the group', () {
      const e = HomeEntry(title: 'X', description: '', icon: Icons.abc, checklistRow: 0, doc: '');
      final sync = basaHomeSections().firstWhere((s) => s.id == HomeSectionIds.sync);
      final same = sync.adding(sync.groups.first.title, const [e]);
      expect(same.groups.length, sync.groups.length);
      expect(same.groups.first.entries.last, e);
      final more = sync.adding('New', const [e]);
      expect(more.groups.length, sync.groups.length + 1);
      expect(more.groups.last.title, 'New');
    });
  });

  test('greetingFor', () {
    expect(greetingFor(DateTime(2026, 1, 1, 8)), 'Good morning');
    expect(greetingFor(DateTime(2026, 1, 1, 13)), 'Good afternoon');
    expect(greetingFor(DateTime(2026, 1, 1, 20)), 'Good evening');
  });

  testWidgets('an entry without a screen opens "Coming soon"', (tester) async {
    const entry = HomeEntry(
      title: 'Users',
      description: 'Accounts',
      icon: Icons.people,
      checklistRow: 12,
      doc: 'admin.md#users',
    );
    await tester.pumpWidget(const MaterialApp(home: NotBuiltScreen(entry: entry)));
    expect(find.text('Users'), findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);
  });
}
