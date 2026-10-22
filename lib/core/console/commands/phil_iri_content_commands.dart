// lib/core/console/commands/phil_iri_content_commands.dart

/// Commands for Phil-IRI content (online): material collections, rubric
/// criteria, passages, comprehension questions and thresholds.
library;


import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/phil_iri_content_viewmodel.dart';
import '../../models/phil_iri_question.dart';
import '../../services/phil_iri_rules.dart';
import 'phil_iri_content_command_helpers.dart';

void registerPhilIriContentCommands(ConsoleRegistry registry, PhilIriContentViewModel vm) {
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

  // ---- Collections ----

  add('phil-iri-collections', 'phil-iri-collections [active] — list the material collections you can see',
      (args) async {
    await vm.loadCollections(activeOnly: args.isNotEmpty && args[0] == 'active');
    if (vm.collections.isEmpty) return 'No collections.';
    return vm.collections.map(philIriContentCollectionLine).join('\n');
  });

  // ---- Rubric criteria ----

  add('phil-iri-criteria', 'phil-iri-criteria <collectionId> — list a collection\'s rubric criteria', (args) async {
    if (args.length != 1) throw const PhilIriContentUsage('Usage: phil-iri-criteria <collectionId>');
    final list = await vm.criteria(philIriContentInt(args[0], 'collectionId'));
    if (list.isEmpty) return 'No rubric criteria.';
    return list.map((k) => '[${k.id}] #${k.criterionNo} ${k.name} (${k.scaleMin}..${k.scaleMax})').join('\n');
  });

  // ---- Passages ----

  add('phil-iri-passages', 'phil-iri-passages <collectionId> [active] — list a collection\'s passages', (args) async {
    if (args.isEmpty) throw const PhilIriContentUsage('Usage: phil-iri-passages <collectionId> [active]');
    final list = await vm.passages(philIriContentInt(args[0], 'collectionId'), activeOnly: args.length > 1 && args[1] == 'active');
    if (list.isEmpty) return 'No passages.';
    return list.map(philIriContentPassageLine).join('\n');
  });

  add('phil-iri-passage-show',
      'phil-iri-passage-show <passageId> — the passage text with word positions (for miscues) and its questions',
      (args) async {
    if (args.length != 1) throw const PhilIriContentUsage('Usage: phil-iri-passage-show <passageId>');
    final p = await vm.getPassage(philIriContentInt(args[0], 'passageId'));
    final words = p.words;
    final out = StringBuffer(philIriContentPassageLine(p));
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

  // ---- Thresholds ----

  add('phil-iri-thresholds', 'phil-iri-thresholds [schoolId] — region and school threshold rows and the values that apply',
      (args) async {
    final schoolId = args.isEmpty ? null : philIriContentInt(args[0], 'schoolId');
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
}
