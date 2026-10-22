// lib/core/wiring/app_context.dart
// What every entry point (admin/tutor app, admin/tutor console) builds first.
// Pure Dart: the caller sets `databaseFactory` before calling [AppContext.open].
import 'package:sqflite_common/sqflite.dart';

import '../../viewmodels/auth_viewmodel.dart';
import '../console/console_registry.dart';
import '../console/console_session.dart';
import '../data/local/local_database.dart';
import '../data/local/login_log_repository_sqlite.dart';
import '../data/local/offline_credential_repository_sqlite.dart';
import '../data/local/report_setting_repository_sqlite.dart';
import '../data/local/user_repository_sqlite.dart';
import '../data/remote/migration_ledger_repository_supabase.dart';
import '../data/remote/supabase_config.dart';
import '../data/remote/user_repository_supabase.dart';
import '../viewmodels/viewmodel_registry.dart';

class AppContext {
  final Database localDb;
  final String dataDir;
  final SupabaseConfigStore config;
  final ConsoleSession session;
  final ConsoleRegistry registry;
  final ViewModelRegistry vmRegistry;
  final AuthViewModel authVm;

  AppContext._({
    required this.localDb,
    required this.dataDir,
    required this.config,
    required this.session,
    required this.registry,
    required this.vmRegistry,
    required this.authVm,
  });

  static Future<AppContext> open({required String dataDir}) async {
    final localDb = await LocalDatabase.instance(dataDir);
    final registry = ConsoleRegistry();
    final session = ConsoleSession(registry);
    final config = await SupabaseConfigStore.load(dataDir);
    final authVm = AuthViewModel(
      loginLogRepo: LoginLogRepositorySqlite(localDb),
      config: config,
      userRepoFactory: (client) => UserRepositorySupabase(client),
      ledgerRepoFactory: (client) => MigrationLedgerRepositorySupabase(client),
      credentials: OfflineCredentialRepositorySqlite(localDb),
      localUsers: UserRepositorySqlite(localDb),
      localReportSettings: ReportSettingRepositorySqlite(localDb),
      logger: session,
    );
    return AppContext._(
      localDb: localDb,
      dataDir: dataDir,
      config: config,
      session: session,
      registry: registry,
      vmRegistry: ViewModelRegistry(),
      authVm: authVm,
    );
  }
}
