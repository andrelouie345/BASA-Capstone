// lib/core/wiring/wire_admin.dart
// Admin build only (admins, coordinators): user management, SF1 import, the
// sync approver, login logs, CRLA scoresheet import, ARAL reports and roster
// import. Never imported from the tutor entry points (tool/check_tutor_imports.dart).
import '../../viewmodels/admin_bootstrap_viewmodel.dart';
import '../../viewmodels/admin_viewmodels.dart';
import '../../viewmodels/aral_report_viewmodel.dart';
import '../../viewmodels/aral_roster_import_viewmodel.dart';
import '../../viewmodels/crla_import_viewmodel.dart';
import '../../viewmodels/import_viewmodel.dart';
import '../../viewmodels/learner_history_viewmodel.dart';
import '../../viewmodels/login_log_viewmodel.dart';
import '../../viewmodels/sync_review_viewmodel.dart';
import '../../viewmodels/tutor_section_assignment_viewmodel.dart';
import '../../viewmodels/user_viewmodel.dart';
import '../console/commands/admin_bootstrap_commands.dart';
import '../console/commands/aral_admin_commands.dart';
import '../console/commands/aral_checkin_admin_commands.dart';
import '../console/commands/aral_class_admin_commands.dart';
import '../console/commands/aral_export_commands.dart';
import '../console/commands/aral_material_admin_commands.dart';
import '../console/commands/aral_report_commands.dart';
import '../console/commands/calendar_admin_commands.dart';
import '../console/commands/crla_import_admin_commands.dart';
import '../console/commands/crla_threshold_admin_commands.dart';
import '../console/commands/import_commands.dart';
import '../console/commands/login_commands.dart';
import '../console/commands/nla_report_commands.dart';
import '../console/commands/phil_iri_admin_commands.dart';
import '../console/commands/phil_iri_content_admin_commands.dart';
import '../console/commands/reminder_admin_commands.dart';
import '../console/commands/report_settings_commands.dart';
import '../console/commands/school_admin_commands.dart';
import '../console/commands/section_admin_commands.dart';
import '../console/commands/srp_admin_commands.dart';
import '../console/commands/sync_admin_commands.dart';
import '../console/commands/trend_admin_commands.dart';
import '../console/commands/tutor_section_commands.dart';
import '../console/commands/user_commands.dart';
import '../data/local/aral_class_repository_sqlite.dart';
import '../data/local/aral_enrollment_repository_sqlite.dart';
import '../data/local/crla_assessment_repository_sqlite.dart';
import '../data/local/crla_result_repository_sqlite.dart';
import '../data/local/aral_session_repository_sqlite.dart';
import '../data/local/learner_history_repository_sqlite.dart';
import '../data/local/phil_iri_assessment_repository_sqlite.dart';
import '../data/local/phil_iri_gst_repository_sqlite.dart';
import '../data/local/login_log_repository_sqlite.dart';
import '../data/remote/login_log_repository_supabase.dart';
import '../data/local/school_repository_sqlite.dart';
import '../data/local/section_repository_sqlite.dart';
import '../data/local/student_repository_sqlite.dart';
import '../data/local/sync_review_local_sqlite.dart';
import '../data/local/user_repository_sqlite.dart';
import '../data/remote/import_conflict_repository_supabase.dart';
import '../data/remote/school_repository_supabase.dart';
import '../data/remote/section_repository_supabase.dart';
import '../data/remote/student_repository_supabase.dart';
import '../data/remote/sync_remote_supabase.dart';
import '../data/remote/tutor_section_assignment_repository_supabase.dart';
import '../data/remote/user_repository_supabase.dart';
import '../services/admin_bootstrap_service.dart';
import '../services/sf1_column_map.dart';
import 'app_context.dart';
import 'wire_shared.dart';
import 'wire_tutor.dart';

class AdminVms {
  final AdminBootstrapViewModel bootstrapVm;
  final UserViewModel userVm;
  final ImportViewModel importVm;
  final SyncReviewViewModel syncReviewVm;
  final LoginLogViewModel loginLogVm;
  final CrlaImportViewModel crlaImportVm;
  final AralReportViewModel aralReportVm;
  final AralRosterImportViewModel aralRosterImportVm;
  final TutorSectionAssignmentViewModel tutorSectionVm;
  final LearnerHistoryViewModel learnerHistoryVm;

  AdminVms({
    required this.bootstrapVm,
    required this.userVm,
    required this.importVm,
    required this.syncReviewVm,
    required this.loginLogVm,
    required this.crlaImportVm,
    required this.aralReportVm,
    required this.aralRosterImportVm,
    required this.tutorSectionVm,
    required this.learnerHistoryVm,
  });
}

/// What admin-build screens get on top of AppViewModels (ui/admin/admin_scope.dart).
AdminViewModels adminViewModels(AdminVms a) => AdminViewModels(
      bootstrap: a.bootstrapVm,
      users: a.userVm,
      tutorSections: a.tutorSectionVm,
      loginLogs: a.loginLogVm,
      syncReview: a.syncReviewVm,
      sf1Import: a.importVm,
      crlaImport: a.crlaImportVm,
      aralRosterImport: a.aralRosterImportVm,
      aralReport: a.aralReportVm,
      learnerHistory: a.learnerHistoryVm,
    );

Future<AdminVms> wireAdmin(AppContext ctx, SharedVms s, TutorVms t) async {
  final db = ctx.localDb;
  final session = ctx.session;
  final vms = ctx.vmRegistry;
  final authVm = ctx.authVm;

  final bootstrapVm = AdminBootstrapViewModel(
      config: ctx.config, serviceFor: AdminBootstrapService.new, logger: session);
  vms.register('AdminBootstrapViewModel', bootstrapVm);

  final userVm = UserViewModel(
      auth: authVm, repoFactory: UserRepositorySupabase.new, local: UserRepositorySqlite(db), logger: session);
  vms.register('UserViewModel', userVm);

  final columnMap = await Sf1ColumnMap.load(ctx.dataDir);
  final importVm = ImportViewModel(
    auth: authVm,
    cloudFactory: (client) => ImportCloudRepos(
      schools: SchoolRepositorySupabase(client),
      sections: SectionRepositorySupabase(client),
      students: StudentRepositorySupabase(client),
      conflicts: ImportConflictRepositorySupabase(client),
    ),
    localSchools: SchoolRepositorySqlite(db),
    localSections: s.sectionRepo,
    localStudents: s.studentRepo,
    columnMap: columnMap,
    logger: session,
  );
  vms.register('ImportViewModel', importVm);

  final syncReviewVm = SyncReviewViewModel(
    auth: authVm,
    local: SyncReviewLocalSqlite(db),
    remote: SyncRemoteSupabase.new,
    logger: session,
  );
  vms.register('SyncReviewViewModel', syncReviewVm);

  final loginLogVm = LoginLogViewModel(
      repo: LoginLogRepositorySqlite(db), auth: authVm, cloudFor: LoginLogRepositorySupabase.new, logger: session);
  vms.register('LoginLogViewModel', loginLogVm);

  final crlaImportVm = CrlaImportViewModel(
    auth: authVm,
    crla: t.crlaVm,
    assessments: CrlaAssessmentRepositorySqlite(db),
    sections: SectionRepositorySqlite(db),
    students: StudentRepositorySqlite(db),
    logger: session,
  );
  vms.register('CrlaImportViewModel', crlaImportVm);

  final aralReportVm = AralReportViewModel(
    auth: authVm,
    roster: AralEnrollmentRepositorySqlite(db),
    sections: SectionRepositorySqlite(db),
    students: StudentRepositorySqlite(db),
    crlaResults: CrlaResultRepositorySqlite(db),
    philIri: t.philIriVm,
    logger: session,
  );
  vms.register('AralReportViewModel', aralReportVm);

  final aralRosterImportVm = AralRosterImportViewModel(
    auth: authVm,
    aral: t.aralVm,
    roster: AralEnrollmentRepositorySqlite(db),
    classes: AralClassRepositorySqlite(db),
    sections: SectionRepositorySqlite(db),
    students: StudentRepositorySqlite(db),
    logger: session,
  );
  vms.register('AralRosterImportViewModel', aralRosterImportVm);

  final tutorSectionVm = TutorSectionAssignmentViewModel(
    auth: authVm,
    repoFactory: TutorSectionAssignmentRepositorySupabase.new,
    local: s.tutorSectionRepo,
    logger: session,
  );
  vms.register('TutorSectionAssignmentViewModel', tutorSectionVm);

  final learnerHistoryVm = LearnerHistoryViewModel(
    auth: authVm,
    history: LearnerHistoryRepositorySqlite(db),
    crlaResults: CrlaResultRepositorySqlite(db),
    philIriSessions: PhilIriAssessmentRepositorySqlite(db),
    gst: PhilIriGstRepositorySqlite(db),
    philIri: t.philIriVm,
    checkins: t.aralCheckinVm,
    sessions: AralSessionRepositorySqlite(db),
    classes: AralClassRepositorySqlite(db),
    users: UserRepositorySqlite(db),
    sections: SectionRepositorySqlite(db),
    logger: session,
  );
  vms.register('LearnerHistoryViewModel', learnerHistoryVm);

  return AdminVms(
    userVm: userVm,
    importVm: importVm,
    syncReviewVm: syncReviewVm,
    loginLogVm: loginLogVm,
    bootstrapVm: bootstrapVm,
    crlaImportVm: crlaImportVm,
    aralReportVm: aralReportVm,
    aralRosterImportVm: aralRosterImportVm,
    tutorSectionVm: tutorSectionVm,
    learnerHistoryVm: learnerHistoryVm,
  );
}

void registerAdminCommands(AppContext ctx, SharedVms s, TutorVms t, AdminVms a) {
  final r = ctx.registry;
  final authVm = ctx.authVm;
  registerAdminBootstrapCommands(r, a.bootstrapVm);
  registerUserCommands(r, a.userVm);
  registerImportCommands(r, a.importVm);
  registerSchoolAdminCommands(r, s.schoolVm);
  registerSectionAdminCommands(r, s.sectionVm);
  registerTutorSectionCommands(r, a.tutorSectionVm);
  registerSyncReviewCommands(r, a.syncReviewVm);
  registerLoginCommands(r, a.loginLogVm);
  registerCrlaImportCommands(r, authVm, a.crlaImportVm);
  registerCrlaThresholdAdminCommands(r, t.crlaThresholdVm);
  registerPhilIriContentAdminCommands(r, t.philIriContentVm);
  registerPhilIriAdminCommands(r, t.philIriVm);
  registerAralAdminCommands(r, t.aralVm);
  registerAralClassAdminCommands(r, t.aralClassVm);
  registerAralCheckinAdminCommands(r, t.aralCheckinVm);
  registerAralMaterialAdminCommands(r, t.aralMaterialVm, t.aralVm);
  registerCalendarAdminCommands(r, t.calendarVm);
  registerReportSettingsCommands(r, t.reportSettingsVm);
  registerNlaReportCommands(r, t.nlaReportVm);
  registerReminderAdminCommands(r, t.reminderVm);
  registerTrendAdminCommands(r, t.trendVm);
  registerSrpAdminCommands(r, t.srpVm);
  registerAralReportCommands(r, a.aralReportVm);
  registerAralExportCommands(r, t.aralVm, a.aralReportVm, t.aralCheckinVm);
  registerAralRosterImportCommands(r, a.aralRosterImportVm);
}
