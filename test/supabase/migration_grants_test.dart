// Every migration from 20261025010000 on that creates a table or view in
// public grants it explicitly in the same file: since 2026-10-30 Supabase no
// longer grants new tables to the API roles (migration 20261025010000).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _firstChecked = '20261025010000';

String _stripComments(String sql) =>
    sql.split('\n').map((l) => l.replaceFirst(RegExp(r'--.*'), '')).join('\n');

/// Tables and views the SQL creates in public (unqualified names count as
/// public; temp tables don't count).
List<String> createdRelations(String sql) {
  final re = RegExp(
      r'create\s+(?:or\s+replace\s+)?(?:materialized\s+)?(?:table|view)\s+(?:if\s+not\s+exists\s+)?'
      r'(?:"?(\w+)"?\.)?"?(\w+)"?',
      caseSensitive: false);
  return [
    for (final m in re.allMatches(_stripComments(sql)))
      if (m.group(1) == null || m.group(1)!.toLowerCase() == 'public') m.group(2)!.toLowerCase(),
  ];
}

/// Created relations with no grant to authenticated in the same SQL.
List<String> ungranted(String sql) {
  final grants = _stripComments(sql)
      .toLowerCase()
      .split(';')
      .map((s) => s.trim())
      .where((s) => s.startsWith('grant') && RegExp(r'\bto\b[^;]*\bauthenticated\b').hasMatch(s))
      .toList();
  bool granted(String name) => grants.any((g) =>
      g.contains('on all tables in schema public') ||
      RegExp('\\bpublic\\."?${RegExp.escape(name)}"?(?![\\w])').hasMatch(g));
  return [
    for (final name in createdRelations(sql))
      if (!granted(name)) name,
  ];
}

void main() {
  group('rule', () {
    test('a table without a grant is caught', () {
      expect(ungranted('create table if not exists public.foo (id int);'), ['foo']);
      expect(ungranted('CREATE OR REPLACE VIEW public.bar AS select 1;'), ['bar']);
    });

    test('a grant to authenticated satisfies it', () {
      expect(
          ungranted('create table public.foo (id int);\n'
              'grant select, insert on public.foo to authenticated, service_role;'),
          isEmpty);
    });

    test('a grant to anon only, a commented grant or a grant on another table does not', () {
      expect(ungranted('create table public.foo (id int); grant select on public.foo to anon;'), ['foo']);
      expect(ungranted('create table public.foo (id int);\n-- grant select on public.foo to authenticated;'),
          ['foo']);
      expect(ungranted('create table public.foo (id int); grant select on public.foobar to authenticated;'),
          ['foo']);
    });

    test('other schemas and temp tables are not checked', () {
      expect(ungranted('create table basa_private.x (id int); create temp table t (id int);'), isEmpty);
    });
  });

  test('migrations from $_firstChecked grant every table and view they create', () {
    final files = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .where((f) => f.uri.pathSegments.last.compareTo(_firstChecked) >= 0)
        .toList();
    expect(files, isNotEmpty, reason: 'run from the repo root');
    final problems = <String>[
      for (final f in files)
        for (final name in ungranted(f.readAsStringSync()))
          '${f.uri.pathSegments.last}: public.$name has no grant to authenticated',
    ];
    expect(problems, isEmpty,
        reason: 'add the grants in the same migration (see 20261025010000_explicit_api_grants.sql)');
  });
}
