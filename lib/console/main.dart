// lib/console/main.dart
import 'dart:io';
import 'package:basa_capstone/core/console/commands/config_commands.dart';
import 'package:basa_capstone/core/console/commands/student_commands.dart';
import 'package:basa_capstone/core/data/local/import_conflict_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/school_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/section_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/student_repository_sqlite.dart';
import 'package:basa_capstone/core/data/remote/supabase_config.dart';
import 'package:basa_capstone/core/services/roster_exporter.dart';
import 'package:basa_capstone/core/services/sf1_importer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common/sqflite.dart';
import '../core/data/local/local_database.dart';
import '../core/data/local/test_repository_sqlite.dart';
import '../core/console/console_registry.dart';
import '../core/console/console_session.dart';
import '../core/console/commands/text_commands.dart';
import '../core/console/commands/debug_commands.dart';
import '../core/console/commands/test_data_commands.dart';
import '../core/viewmodels/viewmodel_registry.dart';
import '../viewmodels/text_viewmodel.dart';
import '../viewmodels/test_data_viewmodel.dart';

Future<void> main() async {
  // Pure `dart run` has no Flutter engine, so we MUST use the FFI
  // factory here — the native `sqflite` plugin would throw
  // MissingPluginException since there's no platform channel at all.
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // No path_provider here (it needs Flutter). Use a local ./data folder.
  final dir = Directory('${Directory.current.path}/data');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final localDb = await LocalDatabase.instance(dir.path);

  final registry = ConsoleRegistry();
  final session = ConsoleSession(registry);
  final vmRegistry = ViewModelRegistry();

  final textVm = TextViewModel(logger: session);
  vmRegistry.register('TextViewModel', textVm);
  registerTextCommands(registry, textVm);

  final testDataVm = TestDataViewModel(repo: TestRepositorySqlite(localDb), logger: session);
  vmRegistry.register('TestDataViewModel', testDataVm);

  final schoolRepo = SchoolRepositorySqlite(localDb);
  final sectionRepo = SectionRepositorySqlite(localDb);
  final studentRepo = StudentRepositorySqlite(localDb);
  final conflictRepo = ImportConflictRepositorySqlite(localDb);
  final importer = Sf1Importer(
    schoolRepo: schoolRepo, sectionRepo: sectionRepo,
    studentRepo: studentRepo, conflictRepo: conflictRepo, logger: session,
  );
  final exporter = RosterExporter();

  final config = await SupabaseConfigStore.load(dir.path);
  registerStudentCommands(registry, importer, exporter, sectionRepo, studentRepo, conflictRepo);
  registerConfigCommands(registry, config);
  registerTestDataCommands(registry, testDataVm, localDb, config);

  registerDebugCommands(registry, session, vmRegistry);
}