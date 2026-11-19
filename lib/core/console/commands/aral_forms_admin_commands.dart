// lib/core/console/commands/aral_forms_admin_commands.dart

/// ARAL Forms 1, 2 and 4 (Reading), Division Memorandum 180 s. 2026, written
/// as .xlsx from the device copy (ARAL memo Plan B Task 6). Admin build only
/// (wholly admin file, tool/check_tutor_imports.dart).
library;

import 'dart:io';

import '../console_command.dart';
import '../console_registry.dart';
import '../date_args.dart';
import '../../../viewmodels/aral_forms_viewmodel.dart';
import '../../../viewmodels/auth_viewmodel.dart';

class _Usage implements Exception {
  final String message;
  const _Usage(this.message);
}

int _int(String raw, String what, String usage) =>
    int.tryParse(raw) ?? (throw _Usage('Invalid $what: "$raw" (expected a number)\n$usage'));

void registerAralFormsAdminCommands(ConsoleRegistry registry, AuthViewModel authVm, AralFormsViewModel vm) {
  void add(String name, String description, Future<String> Function(List<String> args) handler) {
    registry.register(ConsoleCommand(
      name: name,
      description: description,
      handler: (args) async {
        final guardError = authVm.requireActiveSession();
        if (guardError != null) return guardError;
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

  Future<String> write(String path, List<int> bytes) async {
    await File(path).writeAsBytes(bytes);
    return 'Wrote $path (${bytes.length} bytes).';
  }

  add('aral-form1',
      'aral-form1 <schoolId> <schoolYear> <out.xlsx> [classId] — ARAL Form 1 (class list, Reading): one sheet '
          'per class, or one class', (args) async {
    const usage = 'Usage: aral-form1 <schoolId> <schoolYear> <out.xlsx> [classId]';
    if (args.length < 3 || args.length > 4) throw const _Usage(usage);
    final bytes = await vm.form1Xlsx(
      schoolId: _int(args[0], 'schoolId', usage),
      schoolYear: args[1],
      classId: args.length == 4 ? _int(args[3], 'classId', usage) : null,
    );
    return write(args[2], bytes);
  });

  add('aral-form2', 'aral-form2 <schoolId> <schoolYear> <out.xlsx> — ARAL Form 2 (classes, Reading)', (args) async {
    const usage = 'Usage: aral-form2 <schoolId> <schoolYear> <out.xlsx>';
    if (args.length != 3) throw const _Usage(usage);
    final bytes = await vm.form2Xlsx(schoolId: _int(args[0], 'schoolId', usage), schoolYear: args[1]);
    return write(args[2], bytes);
  });

  add('aral-form4',
      'aral-form4 <schoolId> <schoolYear> <out.xlsx> [asof=YYYY-MM-DD] — ARAL Form 4 (progress report, Reading) '
          'as of a date (default today)', (args) async {
    const usage = 'Usage: aral-form4 <schoolId> <schoolYear> <out.xlsx> [asof=YYYY-MM-DD]';
    if (args.length < 3 || args.length > 4) throw const _Usage(usage);
    String? asOf;
    if (args.length == 4) {
      final a = args[3];
      if (!a.startsWith('asof=')) throw const _Usage(usage);
      final d = strictDateArg(a.substring(5)) ?? (throw _Usage(asofDateMessage(a.substring(5))));
      asOf = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
    }
    final now = DateTime.now();
    asOf ??= '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final bytes =
        await vm.form4Xlsx(schoolId: _int(args[0], 'schoolId', usage), schoolYear: args[1], asOf: asOf);
    return write(args[2], bytes);
  });
}
