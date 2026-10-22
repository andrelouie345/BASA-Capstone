// lib/core/console/commands/phil_iri_admin_commands.dart
// Admin build only: the admin half of phil_iri_commands.dart (tutor build split, 2026-10-22).

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/phil_iri_viewmodel.dart';
import '../../models/phil_iri_assessment.dart';
import 'phil_iri_command_helpers.dart';

void registerPhilIriAdminCommands(ConsoleRegistry registry, PhilIriViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        try {
          return await handler(args);
        } on PhilIriUsage catch (e) {
          return e.message;
        } catch (e) {
          return '$name failed: $e';
        }
      },
    ));
  }

  add('phil-iri-finalize',
      'phil-iri-finalize <assessmentId> — admin/coordinator: freeze a completed session with today\'s thresholds',
      (args) async {
    if (args.length != 1) throw const PhilIriUsage('Usage: phil-iri-finalize <assessmentId>');
    final s = await vm.finalize(philIriInt(args[0], 'assessmentId'));
    return 'Session ${s.id} is ${s.status.value} (${s.finalizedAt}).';
  });

  add(
      'phil-iri-finalize-round',
      'phil-iri-finalize-round <sectionId> <schoolYear> <round> — admin/coordinator: close a round '
          '(finalizes each learner\'s completed latest attempt)', (args) async {
    if (args.length != 3) throw const PhilIriUsage('Usage: phil-iri-finalize-round <sectionId> <schoolYear> <round>');
    final c = await vm.finalizeRound(sectionId: philIriInt(args[0], 'sectionId'), schoolYear: args[1], round: philIriRound(args[2]));
    String ids(List<PhilIriAssessment> list) =>
        list.isEmpty ? 'none' : list.map((s) => '${s.id} (student ${s.studentId})').join(', ');
    return 'Finalized: ${ids(c.finalized)}\nStill in progress: ${ids(c.stillInProgress)}\n'
        'Already finalized: ${ids(c.alreadyFinalized)}';
  });
}
