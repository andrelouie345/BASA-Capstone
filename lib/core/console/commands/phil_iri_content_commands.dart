// lib/core/console/commands/phil_iri_content_commands.dart

/// Commands for Phil-IRI content (online): material collections, rubric
/// criteria, passages, comprehension questions and thresholds.
library;

import 'dart:io';

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/phil_iri_content_viewmodel.dart';
import '../../models/phil_iri_collection.dart';
import '../../models/phil_iri_passage.dart';
import '../../models/phil_iri_question.dart';
import '../../services/phil_iri_rules.dart';

void registerPhilIriContentCommands(ConsoleRegistry registry, PhilIriContentViewModel vm) {
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

  // The local copy of a write can fail after the cloud accepted it.
  String done(String message) =>
      vm.lastMirrorWarning == null ? message : '$message\nWARNING: ${vm.lastMirrorWarning}';

  // ---- Collections ----

  add('phil-iri-collections', 'phil-iri-collections [active] — list the material collections you can see',
      (args) async {
    await vm.loadCollections(activeOnly: args.isNotEmpty && args[0] == 'active');
    if (vm.collections.isEmpty) return 'No collections.';
    return vm.collections.map(_collectionLine).join('\n');
  });

  add(
      'phil-iri-collection-add',
      'phil-iri-collection-add <schoolId|region> <name> [ungraded] [nocomp] [prescribed] [order=5,1,2] '
          '— create a collection (quote names with spaces)', (args) async {
    const usage = 'Usage: phil-iri-collection-add <schoolId|region> <name> [ungraded] [nocomp] [prescribed] [order=5,1,2]';
    if (args.length < 2) throw const _Usage(usage);
    final schoolId = args[0] == 'region' ? null : _int(args[0], 'schoolId');
    var graded = true, comprehension = true, prescribed = false;
    List<int>? order;
    for (final flag in args.skip(2)) {
      switch (flag) {
        case 'ungraded':
          graded = false;
        case 'nocomp':
          comprehension = false;
        case 'prescribed':
          prescribed = true;
        case final f when f.startsWith('order='):
          order = _intList(f.substring(6), 'order');
        default:
          throw _Usage('Unknown option "$flag".\n$usage');
      }
    }
    final c = await vm.createCollection(
        schoolId: schoolId, name: args[1], isGradeLeveled: graded, hasComprehension: comprehension,
        isPrescribed: prescribed, readingOrder: order);
    return done('Created collection ${c.id}: ${_collectionLine(c)}');
  });

  add(
      'phil-iri-collection-edit',
      'phil-iri-collection-edit <id> <name|description|graded|comprehension|prescribed|order> <value> '
          '— change one field (description/order: "-" clears; yes/no for flags)', (args) async {
    const usage = 'Usage: phil-iri-collection-edit <id> <name|description|graded|comprehension|prescribed|order> <value>';
    if (args.length < 3) throw const _Usage(usage);
    final c = await vm.getCollection(_int(args[0], 'id'));
    final value = args.sublist(2).join(' ');
    final m = c.toMap();
    switch (args[1]) {
      case 'name':
        m['name'] = value;
      case 'description':
        m['description'] = value == '-' ? null : value;
      case 'graded':
        m['is_grade_leveled'] = _yesNo(value);
      case 'comprehension':
        m['has_comprehension'] = _yesNo(value);
      case 'prescribed':
        m['is_prescribed'] = _yesNo(value);
      case 'order':
        m['reading_order'] = value == '-' ? null : _intList(value, 'order');
      default:
        throw const _Usage(usage);
    }
    final updated = await vm.updateCollection(PhilIriCollection.fromMap(m));
    return done('Updated: ${_collectionLine(updated)}');
  });

  add('phil-iri-collection-activate', 'phil-iri-collection-activate <id> <on|off> — use or stop using a collection',
      (args) async {
    if (args.length != 2) throw const _Usage('Usage: phil-iri-collection-activate <id> <on|off>');
    final c = await vm.setCollectionActive(_int(args[0], 'id'), _onOff(args[1]));
    return done('Updated: ${_collectionLine(c)}');
  });

  add('phil-iri-collection-promote', 'phil-iri-collection-promote <id> — superadmin: make a school collection region-wide',
      (args) async {
    if (args.length != 1) throw const _Usage('Usage: phil-iri-collection-promote <id>');
    final c = await vm.promoteCollection(_int(args[0], 'id'));
    return done('Promoted: ${_collectionLine(c)}');
  });

  add('phil-iri-collection-delete', 'phil-iri-collection-delete <id> — delete a collection that has no passages',
      (args) async {
    if (args.length != 1) throw const _Usage('Usage: phil-iri-collection-delete <id>');
    final id = _int(args[0], 'id');
    await vm.deleteCollection(id);
    return done('Deleted collection $id.');
  });

  // ---- Rubric criteria ----

  add('phil-iri-criteria', 'phil-iri-criteria <collectionId> — list a collection\'s rubric criteria', (args) async {
    if (args.length != 1) throw const _Usage('Usage: phil-iri-criteria <collectionId>');
    final list = await vm.criteria(_int(args[0], 'collectionId'));
    if (list.isEmpty) return 'No rubric criteria.';
    return list.map((k) => '[${k.id}] #${k.criterionNo} ${k.name} (${k.scaleMin}..${k.scaleMax})').join('\n');
  });

  add('phil-iri-criterion-add',
      'phil-iri-criterion-add <collectionId> <scaleMin> <scaleMax> <name...> — add a rubric criterion (next number)',
      (args) async {
    if (args.length < 4) throw const _Usage('Usage: phil-iri-criterion-add <collectionId> <scaleMin> <scaleMax> <name...>');
    final k = await vm.addCriterion(
        collectionId: _int(args[0], 'collectionId'),
        scaleMin: _int(args[1], 'scaleMin'),
        scaleMax: _int(args[2], 'scaleMax'),
        name: args.sublist(3).join(' '));
    return done('Added criterion ${k.id}: #${k.criterionNo} ${k.name} (${k.scaleMin}..${k.scaleMax}).');
  });

  add(
      'phil-iri-criterion-update',
      'phil-iri-criterion-update <collectionId> <criterionId> <no> <scaleMin> <scaleMax> <name...> '
          '— replace a rubric criterion', (args) async {
    if (args.length < 6) {
      throw const _Usage('Usage: phil-iri-criterion-update <collectionId> <criterionId> <no> <scaleMin> <scaleMax> <name...>');
    }
    final k = await vm.updateCriterion(PhilIriRubricCriterion(
        collectionId: _int(args[0], 'collectionId'),
        id: _int(args[1], 'criterionId'),
        criterionNo: _int(args[2], 'no'),
        scaleMin: _int(args[3], 'scaleMin'),
        scaleMax: _int(args[4], 'scaleMax'),
        name: args.sublist(5).join(' ')));
    return done('Updated criterion ${k.id}: #${k.criterionNo} ${k.name} (${k.scaleMin}..${k.scaleMax}).');
  });

  add('phil-iri-criterion-delete', 'phil-iri-criterion-delete <collectionId> <criterionId> — delete a rubric criterion',
      (args) async {
    if (args.length != 2) throw const _Usage('Usage: phil-iri-criterion-delete <collectionId> <criterionId>');
    final id = _int(args[1], 'criterionId');
    await vm.deleteCriterion(_int(args[0], 'collectionId'), id);
    return done('Deleted criterion $id.');
  });

  // ---- Passages ----

  add('phil-iri-passages', 'phil-iri-passages <collectionId> [active] — list a collection\'s passages', (args) async {
    if (args.isEmpty) throw const _Usage('Usage: phil-iri-passages <collectionId> [active]');
    final list = await vm.passages(_int(args[0], 'collectionId'), activeOnly: args.length > 1 && args[1] == 'active');
    if (list.isEmpty) return 'No passages.';
    return list.map(_passageLine).join('\n');
  });

  add('phil-iri-passage-show',
      'phil-iri-passage-show <passageId> — the passage text with word positions (for miscues) and its questions',
      (args) async {
    if (args.length != 1) throw const _Usage('Usage: phil-iri-passage-show <passageId>');
    final p = await vm.getPassage(_int(args[0], 'passageId'));
    final words = p.words;
    final out = StringBuffer(_passageLine(p));
    if (p.motivation != null) out.write('\nMotivation: ${p.motivation}');
    out.write('\nWords (${words.length}):');
    for (var i = 0; i < words.length; i += 10) {
      final end = (i + 10).clamp(0, words.length);
      out.write('\n  ${'$i'.padLeft(3)}: ${[for (var j = i; j < end; j++) words[j]].join(' ')}');
    }
    final questions = await vm.questions(p.id!);
    for (final q in questions) {
      out.write('\n[${q.id}] Q${q.questionNo}${q.questionType == null ? '' : ' (${q.questionType!.code})'} ${q.prompt}');
      for (var i = 0; i < q.choices.length; i++) {
        final letter = PhilIriQuestion.letterOf(i);
        out.write('\n     ${letter == q.answerKey ? '*' : ' '}$letter. ${q.choices[i]}');
      }
    }
    return out.toString();
  });

  add(
      'phil-iri-passage-add',
      'phil-iri-passage-add <collectionId> <level|-> <wordCount> <textFile> <title...> — add a passage; '
          'the text comes from a UTF-8 file (paragraphs on their own lines), the word count from the source', (args) async {
    if (args.length < 5) {
      throw const _Usage('Usage: phil-iri-passage-add <collectionId> <level|-> <wordCount> <textFile> <title...>');
    }
    final p = await vm.addPassage(PhilIriPassage(
      collectionId: _int(args[0], 'collectionId'),
      level: args[1] == '-' ? null : _int(args[1], 'level'),
      wordCount: _int(args[2], 'wordCount'),
      body: _readText(args[3]),
      title: args.sublist(4).join(' '),
    ));
    return done('Added passage ${p.id}: ${_passageLine(p)}');
  });

  add(
      'phil-iri-passage-edit',
      'phil-iri-passage-edit <passageId> <title|motivation|test|set|selection|level> <value> | '
          '<passageId> text <wordCount> <textFile> — change one field ("-" clears)', (args) async {
    const usage = 'Usage: phil-iri-passage-edit <passageId> <title|motivation|test|set|selection|level> <value>\n'
        '       phil-iri-passage-edit <passageId> text <wordCount> <textFile>';
    if (args.length < 3) throw const _Usage(usage);
    final p = await vm.getPassage(_int(args[0], 'passageId'));
    final value = args.sublist(2).join(' ');
    final clear = value == '-';
    final m = p.toMap();
    switch (args[1]) {
      case 'title':
        m['title'] = value;
      case 'motivation':
        m['motivation'] = clear ? null : value;
      case 'test':
        m['test_type'] = clear ? null : value;
      case 'set':
        m['set_code'] = clear ? null : value;
      case 'selection':
        m['selection_no'] = clear ? null : _int(value, 'selection');
      case 'level':
        m['level'] = clear ? null : _int(value, 'level');
      case 'text':
        if (args.length != 4) throw const _Usage(usage);
        m['word_count'] = _int(args[2], 'wordCount');
        m['body'] = _readText(args[3]);
      default:
        throw const _Usage(usage);
    }
    final updated = await vm.updatePassage(PhilIriPassage.fromMap(m));
    return done('Updated: ${_passageLine(updated)}');
  });

  add('phil-iri-passage-activate', 'phil-iri-passage-activate <passageId> <on|off> — use or stop using a passage',
      (args) async {
    if (args.length != 2) throw const _Usage('Usage: phil-iri-passage-activate <passageId> <on|off>');
    final p = await vm.setPassageActive(_int(args[0], 'passageId'), _onOff(args[1]));
    return done('Updated: ${_passageLine(p)}');
  });

  add('phil-iri-passage-delete', 'phil-iri-passage-delete <passageId> — delete a passage nobody has read',
      (args) async {
    if (args.length != 1) throw const _Usage('Usage: phil-iri-passage-delete <passageId>');
    final id = _int(args[0], 'passageId');
    await vm.deletePassage(id);
    return done('Deleted passage $id.');
  });

  // ---- Questions ----

  add(
      'phil-iri-question-add',
      'phil-iri-question-add <passageId> <key> <L|I|C|-> "<question>" "<choice a>" "<choice b>" ... '
          '— add a comprehension question (next number)', (args) async {
    if (args.length < 6) {
      throw const _Usage('Usage: phil-iri-question-add <passageId> <key> <L|I|C|-> "<question>" "<choice a>" "<choice b>" ...');
    }
    final q = await vm.addQuestion(
      passageId: _int(args[0], 'passageId'),
      answerKey: args[1],
      questionType: _questionType(args[2]),
      prompt: args[3],
      choices: args.sublist(4),
    );
    return done('Added question ${q.id}: Q${q.questionNo}, ${q.choices.length} choices, key ${q.answerKey}.');
  });

  add(
      'phil-iri-question-update',
      'phil-iri-question-update <passageId> <questionId> <no> <key> <L|I|C|-> "<question>" "<choice a>" "<choice b>" ... '
          '— replace a question', (args) async {
    if (args.length < 8) {
      throw const _Usage('Usage: phil-iri-question-update <passageId> <questionId> <no> <key> <L|I|C|-> '
          '"<question>" "<choice a>" "<choice b>" ...');
    }
    final q = await vm.updateQuestion(PhilIriQuestion(
      passageId: _int(args[0], 'passageId'),
      id: _int(args[1], 'questionId'),
      questionNo: _int(args[2], 'no'),
      answerKey: args[3],
      questionType: _questionType(args[4]),
      prompt: args[5],
      choices: args.sublist(6),
    ));
    return done('Updated question ${q.id}: Q${q.questionNo}, ${q.choices.length} choices, key ${q.answerKey}.');
  });

  add('phil-iri-question-delete', 'phil-iri-question-delete <passageId> <questionId> — delete a question',
      (args) async {
    if (args.length != 2) throw const _Usage('Usage: phil-iri-question-delete <passageId> <questionId>');
    final id = _int(args[1], 'questionId');
    await vm.deleteQuestion(_int(args[0], 'passageId'), id);
    return done('Deleted question $id.');
  });

  // ---- Thresholds ----

  add('phil-iri-thresholds', 'phil-iri-thresholds [schoolId] — region and school threshold rows and the values that apply',
      (args) async {
    final schoolId = args.isEmpty ? null : _int(args[0], 'schoolId');
    final layers = await vm.thresholdLayers(schoolId);
    final region = layers.region?.settings ?? const {};
    final school = layers.school?.settings ?? const {};
    final out = StringBuffer('Region row: ${layers.region == null ? 'none (defaults)' : '${region.length} key(s)'}');
    if (schoolId != null) {
      out.write('; school $schoolId override: ${layers.school == null ? 'none' : '${school.length} key(s)'}');
    }
    final defaults = PhilIriThresholds.defaults.toMap();
    layers.effective.toMap().forEach((key, value) {
      final from = school.containsKey(key) ? 'school' : (region.containsKey(key) ? 'region' : 'default');
      final note = from == 'default' ? '' : '   ($from; default ${defaults[key]})';
      out.write('\n  ${key.padRight(32)} $value$note');
    });
    return out.toString();
  });

  add(
      'phil-iri-threshold-set',
      'phil-iri-threshold-set <schoolId|region> <key> <value|clear> — set one threshold '
          '(numbers, true/false, or a list like 2,3; clear = use the layer below)', (args) async {
    if (args.length != 3) throw const _Usage('Usage: phil-iri-threshold-set <schoolId|region> <key> <value|clear>');
    final schoolId = args[0] == 'region' ? null : _int(args[0], 'schoolId');
    final saved = await vm.saveThresholds(schoolId: schoolId, changes: {args[1]: _thresholdValue(args[2])});
    return done('Saved ${schoolId == null ? 'region' : 'school $schoolId'} thresholds: ${saved.settings}');
  });

  add('phil-iri-threshold-reset', 'phil-iri-threshold-reset <schoolId> — remove a school\'s override (region values apply)',
      (args) async {
    if (args.length != 1) throw const _Usage('Usage: phil-iri-threshold-reset <schoolId>');
    final schoolId = _int(args[0], 'schoolId');
    await vm.resetSchoolThresholds(schoolId);
    return done('School $schoolId now uses the region thresholds.');
  });
}

/// A bad argument: the handler returns the message as-is.
class _Usage implements Exception {
  final String message;
  const _Usage(this.message);
}

int _int(String raw, String name) =>
    int.tryParse(raw) ?? (throw _Usage('Invalid $name: "$raw" (expected a number)'));

List<int> _intList(String raw, String name) =>
    raw.split(',').map((s) => _int(s.trim(), name)).toList();

bool _yesNo(String raw) => switch (raw) {
      'yes' => true,
      'no' => false,
      _ => throw _Usage('Expected yes or no (got "$raw")'),
    };

bool _onOff(String raw) => switch (raw) {
      'on' => true,
      'off' => false,
      _ => throw _Usage('Expected on or off (got "$raw")'),
    };

PhilIriQuestionType? _questionType(String raw) {
  if (raw == '-') return null;
  try {
    return PhilIriQuestionType.fromString(raw);
  } on ArgumentError {
    throw _Usage('Question type is L, I, C or - (got "$raw")');
  }
}

/// clear -> null (removes the key); true/false; "2,3" or a number.
Object? _thresholdValue(String raw) => switch (raw) {
      'clear' => null,
      'true' => true,
      'false' => false,
      _ when raw.contains(',') => _intList(raw, 'value'),
      _ => int.tryParse(raw) ?? raw, // the ViewModel names the expected type
    };

String _readText(String path) {
  final file = File(path);
  if (!file.existsSync()) throw _Usage('No such file: $path');
  return file.readAsStringSync().replaceAll('\r\n', '\n');
}

String _collectionLine(PhilIriCollection c) => [
      '[${c.id}] ${c.name}',
      c.schoolId == null ? 'region-wide' : 'school ${c.schoolId}',
      if (c.isPrescribed) 'prescribed',
      c.isGradeLeveled ? 'graded' : 'ungraded',
      c.hasComprehension ? 'comprehension' : 'no comprehension',
      if (c.readingOrder != null) 'order ${c.readingOrder!.join(',')}',
      if (!c.isActive) 'INACTIVE',
    ].join(' · ');

String _passageLine(PhilIriPassage p) => [
      '[${p.id}] ${p.title}',
      'collection ${p.collectionId}',
      if (p.level != null) 'Grade ${p.level}',
      if (p.testType != null) p.testType!,
      if (p.setCode != null) 'set ${p.setCode}',
      if (p.selectionNo != null) 'selection ${p.selectionNo}',
      '${p.wordCount} words',
      if (!p.isActive) 'INACTIVE',
    ].join(' · ');
