// lib/core/console/commands/crla_commands.dart

/// Commands for CRLA assessments
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/auth_viewmodel.dart';
import '../../../viewmodels/crla_viewmodel.dart';

void registerCrlaCommands(ConsoleRegistry registry, AuthViewModel authVm, CrlaViewModel vm) {
  registry.register(ConsoleCommand(
    name: 'crla-start',
    description: 'crla-start <studentId> <sectionId> <schoolId> <schoolYear> <mt|fil|eng> [language] '
        '— start a CRLA attempt (retakes just run it again)',
    handler: (args) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;

      const usage = 'Usage: crla-start <studentId> <sectionId> <schoolId> '
          '<schoolYear> <mt|fil|eng> [language]';
      if (args.length < 5) return usage;

      final studentId = int.tryParse(args[0]);
      final sectionId = int.tryParse(args[1]);
      final schoolId = int.tryParse(args[2]);
      if (studentId == null) return 'Invalid studentId: "${args[0]}" (expected a number)';
      if (sectionId == null) return 'Invalid sectionId: "${args[1]}" (expected a number)';
      if (schoolId == null) return 'Invalid schoolId: "${args[2]}" (expected a number)';

      final schoolYear = args[3];
      final variant = args[4];

      // fil and eng imply their language; mt needs one spelled out.
      final language = args.length > 5
          ? args[5]
          : switch (variant) {
              'fil' => 'Tagalog',
              'eng' => 'English',
              _ => null,
            };
      if (language == null) return 'The mt variant needs a language (e.g. Cebuano).\n$usage';

      try {
        final stored = await vm.startAssessment(
          studentId: studentId,
          schoolId: schoolId,
          sectionId: sectionId,
          schoolYear: schoolYear,
          subjectVariant: variant,
          language: language,
          administeredBy: authVm.currentUser?.id,
        );
        return 'Started assessment ${stored.id} (attempt ${stored.attemptNo}, '
            '$variant, ${stored.language}) for student $studentId.';
      } catch (e) {
        return 'Start failed: $e';
      }
    },
  ));
}