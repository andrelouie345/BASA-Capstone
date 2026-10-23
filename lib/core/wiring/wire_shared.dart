// lib/core/wiring/wire_shared.dart
// Both builds: account, server config, sync (uploader side), the school /
// section / student / tutor-section lists, and the dev-only commands.
import '../../viewmodels/school_viewmodel.dart';
import '../../viewmodels/section_viewmodel.dart';
import '../../viewmodels/student_viewmodel.dart';
import '../../viewmodels/sync_viewmodel.dart';
import '../../viewmodels/test_data_viewmodel.dart';
import '../../viewmodels/text_viewmodel.dart';
import '../../viewmodels/tutor_section_assignment_viewmodel.dart';
import '../console/commands/auth_commands.dart';
import '../console/commands/config_commands.dart';
import '../console/commands/debug_commands.dart';
import '../console/commands/pull_commands.dart';
import '../console/commands/school_commands.dart';
import '../console/commands/section-commands.dart';
import '../console/commands/student_commands.dart';
import '../console/commands/sync_commands.dart';
import '../console/commands/test_data_commands.dart';
import '../console/commands/text_commands.dart';
import '../console/commands/version_commands.dart';
import '../data/local/section_repository_sqlite.dart';
import '../data/local/student_repository_sqlite.dart';
import '../data/local/sync_local_repository_sqlite.dart';
import '../data/local/sync_upload_local_sqlite.dart';
import '../data/local/test_repository_sqlite.dart';
import '../data/local/tutor_section_assignment_repository_sqlite.dart';
import '../data/remote/school_repository_supabase.dart';
import '../data/remote/section_repository_supabase.dart';
import '../data/remote/student_repository_supabase.dart';
import '../data/remote/sync_download_supabase.dart';
import '../data/remote/sync_remote_supabase.dart';
import '../data/remote/tutor_section_assignment_repository_supabase.dart';
import '../services/roster_exporter.dart';
import 'app_context.dart';

class SharedVms {
  final TextViewModel textVm;
  final TestDataViewModel testDataVm;
  final SyncViewModel syncVm;
  final SchoolViewModel schoolVm;
  final SectionViewModel sectionVm;
  final StudentViewModel studentVm;
  final TutorSectionAssignmentViewModel tutorSectionVm;
  final TutorSectionAssignmentRepositorySqlite tutorSectionRepo;
  final RosterExporter exporter;
  final SectionRepositorySqlite sectionRepo;
  final StudentRepositorySqlite studentRepo;

  SharedVms({
    required this.textVm,
    required this.testDataVm,
    required this.syncVm,
    required this.schoolVm,
    required this.sectionVm,
    required this.studentVm,
    required this.tutorSectionVm,
    required this.tutorSectionRepo,
    required this.exporter,
    required this.sectionRepo,
    required this.studentRepo,
  });
}

SharedVms wireShared(AppContext ctx) {
  final db = ctx.localDb;
  final session = ctx.session;
  final vms = ctx.vmRegistry;
  final authVm = ctx.authVm;

  final textVm = TextViewModel(logger: session);
  vms.register('TextViewModel', textVm);
  final testDataVm = TestDataViewModel(repo: TestRepositorySqlite(db), logger: session);
  vms.register('TestDataViewModel', testDataVm);

  final studentVm = StudentViewModel(auth: authVm, repoFactory: StudentRepositorySupabase.new, logger: session);
  vms.register('StudentViewModel', studentVm);
  final schoolVm = SchoolViewModel(auth: authVm, repoFactory: SchoolRepositorySupabase.new, logger: session);
  vms.register('SchoolViewModel', schoolVm);
  final sectionVm = SectionViewModel(auth: authVm, repoFactory: SectionRepositorySupabase.new, logger: session);
  vms.register('SectionViewModel', sectionVm);
  final tutorSectionRepo = TutorSectionAssignmentRepositorySqlite(db);
  final tutorSectionVm = TutorSectionAssignmentViewModel(
    auth: authVm,
    repoFactory: TutorSectionAssignmentRepositorySupabase.new,
    local: tutorSectionRepo,
    logger: session,
  );
  vms.register('TutorSectionAssignmentViewModel', tutorSectionVm);

  final syncVm = SyncViewModel(
    auth: authVm,
    local: SyncLocalRepositorySqlite(db),
    download: SyncDownloadSupabase.new,
    uploadLocal: SyncUploadLocalSqlite(db),
    remote: SyncRemoteSupabase.new,
    logger: session,
  );
  vms.register('SyncViewModel', syncVm);

  return SharedVms(
    textVm: textVm,
    testDataVm: testDataVm,
    syncVm: syncVm,
    schoolVm: schoolVm,
    sectionVm: sectionVm,
    studentVm: studentVm,
    tutorSectionVm: tutorSectionVm,
    tutorSectionRepo: tutorSectionRepo,
    exporter: RosterExporter(),
    sectionRepo: SectionRepositorySqlite(db),
    studentRepo: StudentRepositorySqlite(db),
  );
}

void registerSharedCommands(AppContext ctx, SharedVms s) {
  final r = ctx.registry;
  registerConfigCommands(r, ctx.config);
  registerAuthCommands(r, ctx.authVm);
  registerVersionCommands(r, ctx.authVm);
  registerStudentCommands(r, s.exporter, s.sectionRepo, s.studentRepo, s.studentVm);
  registerSchoolCommands(r, s.schoolVm);
  registerSectionCommands(r, s.sectionVm);
  registerPullCommands(r, s.syncVm);
  registerSyncCommands(r, s.syncVm);
}

/// Debug builds and the consoles only. Call it last, so `list-viewmodels`
/// sees every ViewModel.
void registerDevCommands(AppContext ctx, SharedVms s) {
  final r = ctx.registry;
  registerTextCommands(r, s.textVm);
  registerTestDataCommands(r, s.testDataVm, ctx.localDb, ctx.config);
  registerDebugCommands(r, ctx.session, ctx.vmRegistry);
}
