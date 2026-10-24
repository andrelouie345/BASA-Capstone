// lib/core/console/commands/aral_readability_commands.dart

/// Commands for the ARAL readability log (offline, on this device; only while
/// the school's foundational literacy program (SHARP) is on). One action per
/// command; the ViewModel does the checks. Learners are named by their ARAL
/// enrollment id (aral-roster); entries by the #id aral-readability shows.
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../date_args.dart';
import '../../../viewmodels/aral_readability_viewmodel.dart';

class _Usage implements Exception {
  final String message;
  const _Usage(this.message);
}

int _int(String raw, String what) =>
    int.tryParse(raw) ?? (throw _Usage('Invalid $what: "$raw" (expected a number)'));

DateTime _dateArg(String raw) {
  return strictDateArg(raw) ?? (throw _Usage('Dates are real YYYY-MM-DD dates (got "$raw")'));
}

String _line(AralReadabilityEntry x) {
  final l = x.log;
  final r = x.readability;
  return '#${l.id} | ${l.readOn} | ${l.title} | ${l.words} words, ${l.sentences} sentences, ${l.syllables} syllables'
      ' | reading ease ${r.readingEase.toStringAsFixed(2)} (${r.band?.schoolLevel ?? 'below the scale'})'
      ' | grade level ${r.gradeLevel.toStringAsFixed(2)}${l.source == null ? '' : ' | ${l.source}'}'
      '${l.origin == 'local' ? ' | not uploaded' : ''}';
}

void registerAralReadabilityCommands(ConsoleRegistry registry, AralReadabilityViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          return await handler(args);
        } on _Usage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  add('aral-readability', 'aral-readability <enrollmentId> — the learner\'s readability log with the scores',
      (args) async {
    if (args.length != 1) throw const _Usage('Usage: aral-readability <enrollmentId>');
    final list = await vm.entries(_int(args[0], 'enrollmentId'));
    if (list.isEmpty) return 'No readings logged for this learner yet.';
    final lines = list.map(_line).toList();
    final last = list.last.readability;
    if (last.band != null) lines.add('Latest: ${last.band!.notes}');
    return lines.join('\n');
  });

  add(
      'aral-readability-add',
      'aral-readability-add <enrollmentId> <words> <sentences> <syllables> "<title>" [date=YYYY-MM-DD] '
          '["source=<url or reference>"] [material=<materialId>] — log a selection read with the learner '
          '(title "-" with material= uses the material\'s title)', (args) async {
    const usage = 'Usage: aral-readability-add <enrollmentId> <words> <sentences> <syllables> "<title>" '
        '[date=YYYY-MM-DD] ["source=..."] [material=<materialId>]';
    if (args.length < 5 || args.length > 8) throw const _Usage(usage);
    DateTime? date;
    String? source;
    int? material;
    for (final opt in args.sublist(5)) {
      if (opt.startsWith('date=')) {
        date = _dateArg(opt.substring(5));
      } else if (opt.startsWith('source=')) {
        source = opt.substring(7);
      } else if (opt.startsWith('material=')) {
        material = _int(opt.substring(9), 'materialId');
      } else {
        throw const _Usage(usage);
      }
    }
    final x = await vm.add(
      enrollmentId: _int(args[0], 'enrollmentId'),
      words: _int(args[1], 'words'),
      sentences: _int(args[2], 'sentences'),
      syllables: _int(args[3], 'syllables'),
      title: args[4] == '-' ? null : args[4],
      readOn: date,
      source: source,
      materialId: material,
    );
    return 'Logged ${_line(x)}';
  });

  add(
      'aral-readability-set',
      'aral-readability-set <entryId> <title|counts|date|source> <value...> — correct an entry '
          '(counts = <words> <sentences> <syllables>; source "-" clears it)', (args) async {
    const usage = 'Usage: aral-readability-set <entryId> <title|counts|date|source> <value...>';
    if (args.length < 3) throw const _Usage(usage);
    final id = _int(args[0], 'entryId');
    final value = args.sublist(2).join(' ');
    final x = switch (args[1]) {
      'title' => await vm.update(id, title: value),
      'counts' => args.length == 5
          ? await vm.update(id,
              words: _int(args[2], 'words'), sentences: _int(args[3], 'sentences'), syllables: _int(args[4], 'syllables'))
          : throw const _Usage('Usage: aral-readability-set <entryId> counts <words> <sentences> <syllables>'),
      'date' => await vm.update(id, readOn: _dateArg(value)),
      'source' => await vm.update(id, source: () => value == '-' ? null : value),
      _ => throw const _Usage(usage),
    };
    return 'Saved ${_line(x)}';
  });

  add('aral-readability-delete', 'aral-readability-delete <entryId> — remove an entry', (args) async {
    if (args.length != 1) throw const _Usage('Usage: aral-readability-delete <entryId>');
    final id = _int(args[0], 'entryId');
    await vm.delete(id);
    return 'Deleted readability log entry #$id.';
  });
}
