// lib/core/console/commands/phil_iri_content_admin_commands.dart
// Admin build only: the admin half of phil_iri_content_commands.dart (tutor build split, 2026-10-22).

import 'dart:io';

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/phil_iri_content_viewmodel.dart';
import '../../models/phil_iri_collection.dart';
import '../../models/phil_iri_passage.dart';
import '../../models/phil_iri_question.dart';
import 'phil_iri_content_command_helpers.dart';

void registerPhilIriContentAdminCommands(ConsoleRegistry registry, PhilIriContentViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          return await handler(args);
        } on PhilIriContentUsage catch (e) {
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

  add(
      'phil-iri-collection-add',
      'phil-iri-collection-add <schoolId|region> <name> [ungraded] [nocomp] [prescribed] [order=5,1,2] '
          '— create a collection (quote names with spaces)', (args) async {
    const usage = 'Usage: phil-iri-collection-add <schoolId|region> <name> [ungraded] [nocomp] [prescribed] [order=5,1,2]';
    if (args.length < 2) throw const PhilIriContentUsage(usage);
    final schoolId = args[0] == 'region' ? null : philIriContentInt(args[0], 'schoolId');
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
          throw PhilIriContentUsage('Unknown option "$flag".\n$usage');
      }
    }
    final c = await vm.createCollection(
        schoolId: schoolId, name: args[1], isGradeLeveled: graded, hasComprehension: comprehension,
        isPrescribed: prescribed, readingOrder: order);
    return done('Created collection ${c.id}: ${philIriContentCollectionLine(c)}');
  });

  add(
      'phil-iri-collection-edit',
      'phil-iri-collection-edit <id> <name|description|graded|comprehension|prescribed|order> <value> '
          '— change one field (description/order: "-" clears; yes/no for flags)', (args) async {
    const usage = 'Usage: phil-iri-collection-edit <id> <name|description|graded|comprehension|prescribed|order> <value>';
    if (args.length < 3) throw const PhilIriContentUsage(usage);
    final c = await vm.getCollection(philIriContentInt(args[0], 'id'));
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
        throw const PhilIriContentUsage(usage);
    }
    final updated = await vm.updateCollection(PhilIriCollection.fromMap(m));
    return done('Updated: ${philIriContentCollectionLine(updated)}');
  });

  add('phil-iri-collection-activate', 'phil-iri-collection-activate <id> <on|off> — use or stop using a collection',
      (args) async {
    if (args.length != 2) throw const PhilIriContentUsage('Usage: phil-iri-collection-activate <id> <on|off>');
    final c = await vm.setCollectionActive(philIriContentInt(args[0], 'id'), _onOff(args[1]));
    return done('Updated: ${philIriContentCollectionLine(c)}');
  });

  add('phil-iri-collection-promote', 'phil-iri-collection-promote <id> — superadmin: make a school collection region-wide',
      (args) async {
    if (args.length != 1) throw const PhilIriContentUsage('Usage: phil-iri-collection-promote <id>');
    final c = await vm.promoteCollection(philIriContentInt(args[0], 'id'));
    return done('Promoted: ${philIriContentCollectionLine(c)}');
  });

  add('phil-iri-collection-delete', 'phil-iri-collection-delete <id> — delete a collection that has no passages',
      (args) async {
    if (args.length != 1) throw const PhilIriContentUsage('Usage: phil-iri-collection-delete <id>');
    final id = philIriContentInt(args[0], 'id');
    await vm.deleteCollection(id);
    return done('Deleted collection $id.');
  });

  add('phil-iri-criterion-add',
      'phil-iri-criterion-add <collectionId> <scaleMin> <scaleMax> <name...> — add a rubric criterion (next number)',
      (args) async {
    if (args.length < 4) throw const PhilIriContentUsage('Usage: phil-iri-criterion-add <collectionId> <scaleMin> <scaleMax> <name...>');
    final k = await vm.addCriterion(
        collectionId: philIriContentInt(args[0], 'collectionId'),
        scaleMin: philIriContentInt(args[1], 'scaleMin'),
        scaleMax: philIriContentInt(args[2], 'scaleMax'),
        name: args.sublist(3).join(' '));
    return done('Added criterion ${k.id}: #${k.criterionNo} ${k.name} (${k.scaleMin}..${k.scaleMax}).');
  });

  add(
      'phil-iri-criterion-update',
      'phil-iri-criterion-update <collectionId> <criterionId> <no> <scaleMin> <scaleMax> <name...> '
          '— replace a rubric criterion', (args) async {
    if (args.length < 6) {
      throw const PhilIriContentUsage('Usage: phil-iri-criterion-update <collectionId> <criterionId> <no> <scaleMin> <scaleMax> <name...>');
    }
    final k = await vm.updateCriterion(PhilIriRubricCriterion(
        collectionId: philIriContentInt(args[0], 'collectionId'),
        id: philIriContentInt(args[1], 'criterionId'),
        criterionNo: philIriContentInt(args[2], 'no'),
        scaleMin: philIriContentInt(args[3], 'scaleMin'),
        scaleMax: philIriContentInt(args[4], 'scaleMax'),
        name: args.sublist(5).join(' ')));
    return done('Updated criterion ${k.id}: #${k.criterionNo} ${k.name} (${k.scaleMin}..${k.scaleMax}).');
  });

  add('phil-iri-criterion-delete', 'phil-iri-criterion-delete <collectionId> <criterionId> — delete a rubric criterion',
      (args) async {
    if (args.length != 2) throw const PhilIriContentUsage('Usage: phil-iri-criterion-delete <collectionId> <criterionId>');
    final id = philIriContentInt(args[1], 'criterionId');
    await vm.deleteCriterion(philIriContentInt(args[0], 'collectionId'), id);
    return done('Deleted criterion $id.');
  });

  add(
      'phil-iri-passage-add',
      'phil-iri-passage-add <collectionId> <level|-> <wordCount> <textFile> <title...> — add a passage; '
          'the text comes from a UTF-8 file (paragraphs on their own lines), the word count from the source', (args) async {
    if (args.length < 5) {
      throw const PhilIriContentUsage('Usage: phil-iri-passage-add <collectionId> <level|-> <wordCount> <textFile> <title...>');
    }
    final p = await vm.addPassage(PhilIriPassage(
      collectionId: philIriContentInt(args[0], 'collectionId'),
      level: args[1] == '-' ? null : philIriContentInt(args[1], 'level'),
      wordCount: philIriContentInt(args[2], 'wordCount'),
      body: _readText(args[3]),
      title: args.sublist(4).join(' '),
    ));
    return done('Added passage ${p.id}: ${philIriContentPassageLine(p)}');
  });

  add(
      'phil-iri-passage-edit',
      'phil-iri-passage-edit <passageId> <title|motivation|test|set|selection|level> <value> | '
          '<passageId> text <wordCount> <textFile> — change one field ("-" clears)', (args) async {
    const usage = 'Usage: phil-iri-passage-edit <passageId> <title|motivation|test|set|selection|level> <value>\n'
        '       phil-iri-passage-edit <passageId> text <wordCount> <textFile>';
    if (args.length < 3) throw const PhilIriContentUsage(usage);
    final p = await vm.getPassage(philIriContentInt(args[0], 'passageId'));
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
        m['selection_no'] = clear ? null : philIriContentInt(value, 'selection');
      case 'level':
        m['level'] = clear ? null : philIriContentInt(value, 'level');
      case 'text':
        if (args.length != 4) throw const PhilIriContentUsage(usage);
        m['word_count'] = philIriContentInt(args[2], 'wordCount');
        m['body'] = _readText(args[3]);
      default:
        throw const PhilIriContentUsage(usage);
    }
    final updated = await vm.updatePassage(PhilIriPassage.fromMap(m));
    return done('Updated: ${philIriContentPassageLine(updated)}');
  });

  add('phil-iri-passage-activate', 'phil-iri-passage-activate <passageId> <on|off> — use or stop using a passage',
      (args) async {
    if (args.length != 2) throw const PhilIriContentUsage('Usage: phil-iri-passage-activate <passageId> <on|off>');
    final p = await vm.setPassageActive(philIriContentInt(args[0], 'passageId'), _onOff(args[1]));
    return done('Updated: ${philIriContentPassageLine(p)}');
  });

  add('phil-iri-passage-delete', 'phil-iri-passage-delete <passageId> — delete a passage nobody has read',
      (args) async {
    if (args.length != 1) throw const PhilIriContentUsage('Usage: phil-iri-passage-delete <passageId>');
    final id = philIriContentInt(args[0], 'passageId');
    await vm.deletePassage(id);
    return done('Deleted passage $id.');
  });

  // ---- Questions ----

  add(
      'phil-iri-question-add',
      'phil-iri-question-add <passageId> <key> <L|I|C|-> "<question>" "<choice a>" "<choice b>" ... '
          '— add a comprehension question (next number)', (args) async {
    if (args.length < 6) {
      throw const PhilIriContentUsage('Usage: phil-iri-question-add <passageId> <key> <L|I|C|-> "<question>" "<choice a>" "<choice b>" ...');
    }
    final q = await vm.addQuestion(
      passageId: philIriContentInt(args[0], 'passageId'),
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
      throw const PhilIriContentUsage('Usage: phil-iri-question-update <passageId> <questionId> <no> <key> <L|I|C|-> '
          '"<question>" "<choice a>" "<choice b>" ...');
    }
    final q = await vm.updateQuestion(PhilIriQuestion(
      passageId: philIriContentInt(args[0], 'passageId'),
      id: philIriContentInt(args[1], 'questionId'),
      questionNo: philIriContentInt(args[2], 'no'),
      answerKey: args[3],
      questionType: _questionType(args[4]),
      prompt: args[5],
      choices: args.sublist(6),
    ));
    return done('Updated question ${q.id}: Q${q.questionNo}, ${q.choices.length} choices, key ${q.answerKey}.');
  });

  add('phil-iri-question-delete', 'phil-iri-question-delete <passageId> <questionId> — delete a question',
      (args) async {
    if (args.length != 2) throw const PhilIriContentUsage('Usage: phil-iri-question-delete <passageId> <questionId>');
    final id = philIriContentInt(args[1], 'questionId');
    await vm.deleteQuestion(philIriContentInt(args[0], 'passageId'), id);
    return done('Deleted question $id.');
  });

  add(
      'phil-iri-threshold-set',
      'phil-iri-threshold-set <schoolId|region> <key> <value|clear> — set one threshold '
          '(numbers, true/false, or a list like 2,3; clear = use the layer below)', (args) async {
    if (args.length != 3) throw const PhilIriContentUsage('Usage: phil-iri-threshold-set <schoolId|region> <key> <value|clear>');
    final schoolId = args[0] == 'region' ? null : philIriContentInt(args[0], 'schoolId');
    final saved = await vm.saveThresholds(schoolId: schoolId, changes: {args[1]: _thresholdValue(args[2])});
    return done('Saved ${schoolId == null ? 'region' : 'school $schoolId'} thresholds: ${saved.settings}');
  });

  add('phil-iri-threshold-reset', 'phil-iri-threshold-reset <schoolId> — remove a school\'s override (region values apply)',
      (args) async {
    if (args.length != 1) throw const PhilIriContentUsage('Usage: phil-iri-threshold-reset <schoolId>');
    final schoolId = philIriContentInt(args[0], 'schoolId');
    await vm.resetSchoolThresholds(schoolId);
    return done('School $schoolId now uses the region thresholds.');
  });
}

List<int> _intList(String raw, String name) =>
    raw.split(',').map((s) => philIriContentInt(s.trim(), name)).toList();

bool _yesNo(String raw) => switch (raw) {
      'yes' => true,
      'no' => false,
      _ => throw PhilIriContentUsage('Expected yes or no (got "$raw")'),
    };

bool _onOff(String raw) => switch (raw) {
      'on' => true,
      'off' => false,
      _ => throw PhilIriContentUsage('Expected on or off (got "$raw")'),
    };

PhilIriQuestionType? _questionType(String raw) {
  if (raw == '-') return null;
  try {
    return PhilIriQuestionType.fromString(raw);
  } on ArgumentError {
    throw PhilIriContentUsage('Question type is L, I, C or - (got "$raw")');
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
  if (!file.existsSync()) throw PhilIriContentUsage('No such file: $path');
  return file.readAsStringSync().replaceAll('\r\n', '\n');
}
