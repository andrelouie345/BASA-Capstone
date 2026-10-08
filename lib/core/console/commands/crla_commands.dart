// lib/core/console/commands/crla_commands.dart

/// Commands for CRLA assessments
library;

import '../console_command.dart';
import '../console_registry.dart';
import '../../../viewmodels/auth_viewmodel.dart';
import '../../../viewmodels/crla_viewmodel.dart';
import '../../models/crla_result.dart';

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
    registry.register(ConsoleCommand(
    name: 'crla-part1',
    description: 'crla-part1 <assessmentId> <task1> [task2] — save Part 1 scores '
        '(mt/fil or eng table is chosen from the assessment)',
    handler: (args) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;

      const usage = 'Usage: crla-part1 <assessmentId> <task1Score> [task2Score]';
      if (args.length < 2 || args.length > 3) return usage;

      final assessmentId = int.tryParse(args[0]);
      final task1 = int.tryParse(args[1]);
      final task2 = args.length == 3 ? int.tryParse(args[2]) : null;
      if (assessmentId == null) return 'Invalid assessmentId: "${args[0]}" (expected a number)';
      if (task1 == null) return 'Invalid task1Score: "${args[1]}" (expected a number)';
      if (args.length == 3 && task2 == null) {
        return 'Invalid task2Score: "${args[2]}" (expected a number)';
      }

      try {
        final assessment = await vm.getAssessment(assessmentId);
        if (assessment == null) return 'No assessment with id $assessmentId.';

        if (assessment.subjectVariant == 'eng') {
          final stored = await vm.savePart1English(
            assessmentId: assessmentId,
            task1Score: task1,
            task2Score: task2,
          );
          return 'Saved English Part 1 for assessment $assessmentId: '
              'total ${stored.totalScore}, level ${stored.readingLevel}.';
        }

        // mt/fil: a single task2 value goes to the low or high field by task1.
        final stored = await vm.savePart1Standard(
          assessmentId: assessmentId,
          task1Score: task1,
          task2LowScore: (task2 != null && task1 < 7) ? task2 : null,
          task2HighScore: (task2 != null && task1 >= 7) ? task2 : null,
        );
        return 'Saved Part 1 for assessment $assessmentId: '
            'total ${stored.totalScore}, level ${stored.readingLevel}.';
      } catch (e) {
        return 'Part 1 failed: $e';
      }
    },
  ));
    registry.register(ConsoleCommand(
    name: 'crla-part2',
    description: 'crla-part2 <assessmentId> <storyNo> <miscues> <wordsRead> <minutes> <seconds> '
        '<comprehension> [experience|-] [observation|-] [remarks...] — save Part 2 (fluency)',
    handler: (args) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;

      const usage = 'Usage: crla-part2 <assessmentId> <storyNo> <miscues> <wordsRead> '
          '<minutes> <seconds> <comprehension> [experience|-] [observation|-] [remarks...]';
      if (args.length < 7) return usage;

      final names = ['assessmentId', 'storyNo', 'miscues', 'wordsRead', 'minutes', 'seconds', 'comprehension'];
      final nums = <int>[];
      for (var i = 0; i < 7; i++) {
        final n = int.tryParse(args[i]);
        if (n == null) return 'Invalid ${names[i]}: "${args[i]}" (expected a number)';
        nums.add(n);
      }

      // Optional rating and observation: a number, or "-" to skip it.
      int? optional(int index, String name) {
        if (args.length <= index || args[index] == '-') return null;
        final n = int.tryParse(args[index]);
        if (n == null) throw FormatException('Invalid $name: "${args[index]}" (expected a number or -)');
        return n;
      }

      try {
        final experience = optional(7, 'experience');
        final observation = optional(8, 'observation');
        final remarks = args.length > 9 ? args.sublist(9).join(' ') : null;

        final stored = await vm.savePart2Fluency(
          assessmentId: nums[0],
          storyNo: nums[1],
          miscues: nums[2],
          wordsRead: nums[3],
          timeMinutes: nums[4],
          timeSeconds: nums[5],
          comprehensionCorrect: nums[6],
          learnerExperienceRating: experience,
          observationLevel: observation,
          remarks: remarks,
        );

        final result = await vm.getResult(nums[0]);
        final out = StringBuffer('Saved Part 2 for assessment ${nums[0]}: '
            'wpm ${stored.wpm?.toStringAsFixed(1) ?? "-"}.');
        if (result != null) {
          out.write('\n${_formatResult(result)}');
          if (result.pctCorrectWordsRead == null) {
            out.write('\nNo story matched (check the school\'s region, language, grade and story number).');
          }
        }
        return out.toString();
      } on FormatException catch (e) {
        return e.message;
      } catch (e) {
        return 'Part 2 failed: $e';
      }
    },
  ));

  registry.register(ConsoleCommand(
    name: 'crla-results',
    description: 'crla-results assessment <id> | section <id> [schoolYear] | student <id> '
        '— show combined CRLA results',
    handler: (args) async {
      final guardError = authVm.requireActiveSession();
      if (guardError != null) return guardError;

      const usage = 'Usage: crla-results assessment <id> | section <id> [schoolYear] | student <id>';
      if (args.length < 2) return usage;

      final id = int.tryParse(args[1]);
      if (id == null) return 'Invalid id: "${args[1]}" (expected a number)';

      try {
        switch (args[0]) {
          case 'assessment':
            final r = await vm.getResult(id);
            return r == null ? 'No assessment with id $id.' : _formatResult(r);
          case 'section':
            await vm.loadResultsForSection(id, schoolYear: args.length > 2 ? args[2] : null);
          case 'student':
            await vm.loadResultsForStudent(id);
          default:
            return usage;
        }
        if (vm.results.isEmpty) return '(no results found)';
        return vm.results.map(_formatResult).join('\n');
      } catch (e) {
        return 'Results failed: $e';
      }
    },
  ));
}

String _formatResult(CrlaResult r) {
  final p1 = r.part1TotalScore == null ? '-' : '${r.part1TotalScore} ${r.part1ReadingLevel}';
  final pct = r.pctCorrectWordsRead == null
      ? '-'
      : '${(r.pctCorrectWordsRead! * 100).toStringAsFixed(1)}%';
  return '#${r.assessmentId} | student ${r.studentId} | ${r.subjectVariant} ${r.language} '
      'attempt ${r.attemptNo} | P1 $p1 | '
      'P2 story ${r.storyNo ?? "-"} wpm ${r.wpm?.toStringAsFixed(1) ?? "-"} '
      'comp ${r.comprehensionCorrect ?? "-"} words $pct | ${r.readingProfile ?? "-"}';
}