// lib/core/wiring/wire_tutor.dart
// Both builds: assessing (CRLA, Phil-IRI), ARAL daily work, recommendations,
// tutor reminders, dashboard and trends. NlaReportViewModel, SrpViewModel and
// ReportSettingsViewModel live here because the dashboard, reminders, trends
// and srp-classes need them (owner decision D1, 2026-10-22); their admin-only
// methods are dropped by tree shaking and checked by tool/admin_markers.txt.
import '../../viewmodels/app_viewmodels.dart';
import '../../viewmodels/aral_checkin_viewmodel.dart';
import '../../viewmodels/aral_class_viewmodel.dart';
import '../../viewmodels/aral_irip_viewmodel.dart';
import '../../viewmodels/aral_material_viewmodel.dart';
import '../../viewmodels/aral_readability_viewmodel.dart';
import '../../viewmodels/aral_session_viewmodel.dart';
import '../../viewmodels/aral_viewmodel.dart';
import '../../viewmodels/crla_export_viewmodel.dart';
import '../../viewmodels/crla_threshold_viewmodel.dart';
import '../../viewmodels/crla_viewmodel.dart';
import '../../viewmodels/dashboard_viewmodel.dart';
import '../../viewmodels/nla_report_viewmodel.dart';
import '../../viewmodels/phil_iri_content_viewmodel.dart';
import '../../viewmodels/phil_iri_viewmodel.dart';
import '../../viewmodels/reminder_viewmodel.dart';
import '../../viewmodels/report_settings_viewmodel.dart';
import '../../viewmodels/round_calendar_viewmodel.dart';
import '../../viewmodels/srp_viewmodel.dart';
import '../../viewmodels/trend_viewmodel.dart';
import '../console/commands/aral_checkin_commands.dart';
import '../console/commands/aral_class_commands.dart';
import '../console/commands/aral_commands.dart';
import '../console/commands/aral_irip_commands.dart';
import '../console/commands/aral_material_commands.dart';
import '../console/commands/aral_readability_commands.dart';
import '../console/commands/aral_session_commands.dart';
import '../console/commands/calendar_commands.dart';
import '../console/commands/crla_commands.dart';
import '../console/commands/crla_import_commands.dart';
import '../console/commands/crla_threshold_commands.dart';
import '../console/commands/dashboard_commands.dart';
import '../console/commands/phil_iri_commands.dart';
import '../console/commands/phil_iri_content_commands.dart';
import '../console/commands/reminder_commands.dart';
import '../console/commands/srp_commands.dart';
import '../console/commands/trend_commands.dart';
import '../data/local/aral_checkin_repository_sqlite.dart';
import '../data/local/aral_class_repository_sqlite.dart';
import '../data/local/aral_enrollment_repository_sqlite.dart';
import '../data/local/aral_irip_repository_sqlite.dart';
import '../data/local/aral_material_repository_sqlite.dart';
import '../data/local/aral_readability_repository_sqlite.dart';
import '../data/local/aral_session_repository_sqlite.dart';
import '../data/local/aral_setting_repository_sqlite.dart';
import '../data/local/assessment_calendar_repository_sqlite.dart';
import '../data/local/crla_assessment_repository_sqlite.dart';
import '../data/local/crla_part1_english_repository_sqlite.dart';
import '../data/local/crla_part1_standard_repository_sqlite.dart';
import '../data/local/crla_part2_fluency_repository_sqlite.dart';
import '../data/local/crla_result_repository_sqlite.dart';
import '../data/local/crla_story_repository_sqlite.dart';
import '../data/local/crla_threshold_repository_sqlite.dart';
import '../data/local/phil_iri_assessment_repository_sqlite.dart';
import '../data/local/phil_iri_collection_repository_sqlite.dart';
import '../data/local/phil_iri_gst_repository_sqlite.dart';
import '../data/local/phil_iri_passage_repository_sqlite.dart';
import '../data/local/phil_iri_threshold_repository_sqlite.dart';
import '../data/local/report_setting_repository_sqlite.dart';
import '../data/local/school_repository_sqlite.dart';
import '../data/local/section_repository_sqlite.dart';
import '../data/local/srp_class_repository_sqlite.dart';
import '../data/local/student_repository_sqlite.dart';
import '../data/local/user_repository_sqlite.dart';
import '../data/remote/aral_material_repository_supabase.dart';
import '../data/remote/aral_setting_repository_supabase.dart';
import '../data/remote/assessment_calendar_repository_supabase.dart';
import '../data/remote/crla_assessment_repository_supabase.dart';
import '../data/remote/crla_part1_english_repository_supabase.dart';
import '../data/remote/crla_part1_standard_repository_supabase.dart';
import '../data/remote/crla_threshold_repository_supabase.dart';
import '../data/remote/phil_iri_collection_repository_supabase.dart';
import '../data/remote/phil_iri_passage_repository_supabase.dart';
import '../data/remote/phil_iri_threshold_repository_supabase.dart';
import '../data/remote/report_setting_repository_supabase.dart';
import '../data/remote/srp_class_repository_supabase.dart';
import 'app_context.dart';
import 'wire_shared.dart';

class TutorVms {
  final CrlaViewModel crlaVm;
  final CrlaExportViewModel crlaExportVm;
  final CrlaThresholdViewModel crlaThresholdVm;
  final PhilIriContentViewModel philIriContentVm;
  final PhilIriViewModel philIriVm;
  final AralViewModel aralVm;
  final AralClassViewModel aralClassVm;
  final AralSessionViewModel aralSessionVm;
  final AralIripViewModel aralIripVm;
  final AralCheckinViewModel aralCheckinVm;
  final AralMaterialViewModel aralMaterialVm;
  final AralReadabilityViewModel aralReadabilityVm;
  final RoundCalendarViewModel calendarVm;
  final ReportSettingsViewModel reportSettingsVm;
  final NlaReportViewModel nlaReportVm;
  final ReminderViewModel reminderVm;
  final TrendViewModel trendVm;
  final SrpViewModel srpVm;
  final DashboardViewModel dashboardVm;

  TutorVms({
    required this.crlaVm,
    required this.crlaExportVm,
    required this.crlaThresholdVm,
    required this.philIriContentVm,
    required this.philIriVm,
    required this.aralVm,
    required this.aralClassVm,
    required this.aralSessionVm,
    required this.aralIripVm,
    required this.aralCheckinVm,
    required this.aralMaterialVm,
    required this.aralReadabilityVm,
    required this.calendarVm,
    required this.reportSettingsVm,
    required this.nlaReportVm,
    required this.reminderVm,
    required this.trendVm,
    required this.srpVm,
    required this.dashboardVm,
  });
}

/// What the screens get (ui/basa_scope.dart): the ViewModels only, without
/// the repositories and dev-only ViewModels the wiring also carries.
AppViewModels appViewModels(AppContext ctx, SharedVms s, TutorVms t) => AppViewModels(
      auth: ctx.authVm,
      serverConfig: s.serverConfigVm,
      sync: s.syncVm,
      school: s.schoolVm,
      section: s.sectionVm,
      student: s.studentVm,
      crla: t.crlaVm,
      crlaExport: t.crlaExportVm,
      crlaThresholds: t.crlaThresholdVm,
      philIri: t.philIriVm,
      philIriContent: t.philIriContentVm,
      aral: t.aralVm,
      aralClass: t.aralClassVm,
      aralSession: t.aralSessionVm,
      aralIrip: t.aralIripVm,
      aralCheckin: t.aralCheckinVm,
      aralMaterial: t.aralMaterialVm,
      aralReadability: t.aralReadabilityVm,
      calendar: t.calendarVm,
      reportSettings: t.reportSettingsVm,
      nlaReport: t.nlaReportVm,
      reminders: t.reminderVm,
      trend: t.trendVm,
      srp: t.srpVm,
      dashboard: t.dashboardVm,
    );

TutorVms wireTutor(AppContext ctx, SharedVms s) {
  final db = ctx.localDb;
  final session = ctx.session;
  final vms = ctx.vmRegistry;
  final authVm = ctx.authVm;

  final crlaVm = CrlaViewModel(
    stories: CrlaStoryRepositorySqlite(db),
    assessments: CrlaAssessmentRepositorySqlite(db),
    part1Standard: CrlaPart1StandardRepositorySqlite(db),
    part1English: CrlaPart1EnglishRepositorySqlite(db),
    part2Fluency: CrlaPart2FluencyRepositorySqlite(db),
    results: CrlaResultRepositorySqlite(db),
    sections: SectionRepositorySqlite(db),
    schools: SchoolRepositorySqlite(db),
    thresholds: CrlaThresholdRepositorySqlite(db),
    auth: authVm,
    logger: session,
  );
  vms.register('CrlaViewModel', crlaVm);
  final crlaExportVm = CrlaExportViewModel(
    auth: authVm,
    sections: SectionRepositorySqlite(db),
    schools: SchoolRepositorySqlite(db),
    students: StudentRepositorySqlite(db),
    assessments: CrlaAssessmentRepositorySqlite(db),
    part1Standard: CrlaPart1StandardRepositorySqlite(db),
    part1English: CrlaPart1EnglishRepositorySqlite(db),
    part2Fluency: CrlaPart2FluencyRepositorySqlite(db),
    stories: CrlaStoryRepositorySqlite(db),
    thresholds: CrlaThresholdRepositorySqlite(db),
    logger: session,
  );
  vms.register('CrlaExportViewModel', crlaExportVm);
  // CRLA thresholds are managed online (mirrored locally); regenerate runs in the cloud.
  final crlaThresholdVm = CrlaThresholdViewModel(
    auth: authVm,
    cloudFactory: (client) => CrlaThresholdCloudRepos(
      thresholds: CrlaThresholdRepositorySupabase(client),
      assessments: CrlaAssessmentRepositorySupabase(client),
      part1Standard: CrlaPart1StandardRepositorySupabase(client),
      part1English: CrlaPart1EnglishRepositorySupabase(client),
    ),
    localThresholds: CrlaThresholdRepositorySqlite(db),
    localAssessments: CrlaAssessmentRepositorySqlite(db),
    localPart1Standard: CrlaPart1StandardRepositorySqlite(db),
    localPart1English: CrlaPart1EnglishRepositorySqlite(db),
    logger: session,
  );
  vms.register('CrlaThresholdViewModel', crlaThresholdVm);

  // Phil-IRI: content is managed online (mirrored locally); assessments are local.
  final philIriContentVm = PhilIriContentViewModel(
    auth: authVm,
    cloudFactory: (client) => PhilIriContentCloudRepos(
      collections: PhilIriCollectionRepositorySupabase(client),
      passages: PhilIriPassageRepositorySupabase(client),
      thresholds: PhilIriThresholdRepositorySupabase(client),
    ),
    localCollections: PhilIriCollectionRepositorySqlite(db),
    localPassages: PhilIriPassageRepositorySqlite(db),
    localThresholds: PhilIriThresholdRepositorySqlite(db),
    logger: session,
  );
  vms.register('PhilIriContentViewModel', philIriContentVm);
  final philIriVm = PhilIriViewModel(
    auth: authVm,
    sessions: PhilIriAssessmentRepositorySqlite(db),
    gst: PhilIriGstRepositorySqlite(db),
    passages: PhilIriPassageRepositorySqlite(db),
    collections: PhilIriCollectionRepositorySqlite(db),
    thresholds: PhilIriThresholdRepositorySqlite(db),
    sections: SectionRepositorySqlite(db),
    logger: session,
  );
  vms.register('PhilIriViewModel', philIriVm);

  final aralVm = AralViewModel(
    auth: authVm,
    roster: AralEnrollmentRepositorySqlite(db),
    classes: AralClassRepositorySqlite(db),
    sections: SectionRepositorySqlite(db),
    students: StudentRepositorySqlite(db),
    users: UserRepositorySqlite(db),
    crlaResults: CrlaResultRepositorySqlite(db),
    philIri: philIriVm,
    localSettings: AralSettingRepositorySqlite(db),
    logger: session,
  );
  vms.register('AralViewModel', aralVm);

  final aralClassVm = AralClassViewModel(
    auth: authVm,
    classes: AralClassRepositorySqlite(db),
    roster: AralEnrollmentRepositorySqlite(db),
    sessions: AralSessionRepositorySqlite(db),
    sections: SectionRepositorySqlite(db),
    students: StudentRepositorySqlite(db),
    users: UserRepositorySqlite(db),
    logger: session,
  );
  vms.register('AralClassViewModel', aralClassVm);

  final aralSessionVm = AralSessionViewModel(
    auth: authVm,
    sessions: AralSessionRepositorySqlite(db),
    roster: AralEnrollmentRepositorySqlite(db),
    users: UserRepositorySqlite(db),
    students: StudentRepositorySqlite(db),
    classes: AralClassRepositorySqlite(db),
    logger: session,
  );
  vms.register('AralSessionViewModel', aralSessionVm);

  final aralIripVm = AralIripViewModel(
    auth: authVm,
    irip: AralIripRepositorySqlite(db),
    roster: AralEnrollmentRepositorySqlite(db),
    logger: session,
  );
  vms.register('AralIripViewModel', aralIripVm);

  // Check-ins are local; the cut-off is set online and mirrored locally.
  final aralCheckinVm = AralCheckinViewModel(
    auth: authVm,
    checkins: AralCheckinRepositorySqlite(db),
    roster: AralEnrollmentRepositorySqlite(db),
    localSettings: AralSettingRepositorySqlite(db),
    cloudSettings: (client) => AralSettingRepositorySupabase(client),
    sections: SectionRepositorySqlite(db),
    students: StudentRepositorySqlite(db),
    logger: session,
  );
  vms.register('AralCheckinViewModel', aralCheckinVm);

  final aralMaterialVm = AralMaterialViewModel(
    auth: authVm,
    local: AralMaterialRepositorySqlite(db),
    cloud: (client) => AralMaterialRepositorySupabase(client),
    roster: AralEnrollmentRepositorySqlite(db),
    sections: SectionRepositorySqlite(db),
    localSettings: AralSettingRepositorySqlite(db),
    logger: session,
  );
  vms.register('AralMaterialViewModel', aralMaterialVm);

  final aralReadabilityVm = AralReadabilityViewModel(
    auth: authVm,
    logs: AralReadabilityRepositorySqlite(db),
    roster: AralEnrollmentRepositorySqlite(db),
    localSettings: AralSettingRepositorySqlite(db),
    materials: AralMaterialRepositorySqlite(db),
    logger: session,
  );
  vms.register('AralReadabilityViewModel', aralReadabilityVm);

  final calendarVm = RoundCalendarViewModel(
    auth: authVm,
    local: AssessmentCalendarRepositorySqlite(db),
    cloud: (client) => AssessmentCalendarRepositorySupabase(client),
    logger: session,
  );
  vms.register('RoundCalendarViewModel', calendarVm);

  final reportSettingsVm = ReportSettingsViewModel(
    auth: authVm,
    local: ReportSettingRepositorySqlite(db),
    cloud: (client) => ReportSettingRepositorySupabase(client),
    logger: session,
  );
  vms.register('ReportSettingsViewModel', reportSettingsVm);

  final nlaReportVm = NlaReportViewModel(
    auth: authVm,
    sections: SectionRepositorySqlite(db),
    students: StudentRepositorySqlite(db),
    philIri: philIriVm,
    reportSettings: reportSettingsVm,
    calendar: calendarVm,
    logger: session,
  );
  vms.register('NlaReportViewModel', nlaReportVm);

  final reminderVm = ReminderViewModel(
    auth: authVm,
    calendar: calendarVm,
    reports: nlaReportVm,
    reportSettings: reportSettingsVm,
    schools: SchoolRepositorySqlite(db),
    sections: SectionRepositorySqlite(db),
    students: StudentRepositorySqlite(db),
    crlaResults: CrlaResultRepositorySqlite(db),
    assignments: s.tutorSectionRepo,
    users: UserRepositorySqlite(db),
    roster: AralEnrollmentRepositorySqlite(db),
    aralSessions: AralSessionRepositorySqlite(db),
    irip: AralIripRepositorySqlite(db),
    checkins: AralCheckinRepositorySqlite(db),
    aralSettings: AralSettingRepositorySqlite(db),
    classes: AralClassRepositorySqlite(db),
    logger: session,
  );
  vms.register('ReminderViewModel', reminderVm);

  final trendVm = TrendViewModel(
    auth: authVm,
    schools: SchoolRepositorySqlite(db),
    sections: SectionRepositorySqlite(db),
    students: StudentRepositorySqlite(db),
    users: UserRepositorySqlite(db),
    crlaResults: CrlaResultRepositorySqlite(db),
    nla: nlaReportVm,
    aral: aralSessionVm,
    aralSessions: AralSessionRepositorySqlite(db),
    logger: session,
  );
  vms.register('TrendViewModel', trendVm);

  final srpVm = SrpViewModel(
    reports: nlaReportVm,
    students: StudentRepositorySqlite(db),
    philIri: philIriVm,
    auth: authVm,
    local: SrpClassRepositorySqlite(db),
    cloud: (client) => SrpClassRepositorySupabase(client),
    users: UserRepositorySqlite(db),
    sections: SectionRepositorySqlite(db),
    logger: session,
  );
  vms.register('SrpViewModel', srpVm);

  final dashboardVm = DashboardViewModel(
    auth: authVm,
    calendar: calendarVm,
    reminders: reminderVm,
    reports: nlaReportVm,
    srp: srpVm,
    aral: aralVm,
    schools: SchoolRepositorySqlite(db),
    sections: SectionRepositorySqlite(db),
    students: StudentRepositorySqlite(db),
    assignments: s.tutorSectionRepo,
    logger: session,
  );
  vms.register('DashboardViewModel', dashboardVm);

  return TutorVms(
    crlaVm: crlaVm,
    crlaExportVm: crlaExportVm,
    crlaThresholdVm: crlaThresholdVm,
    philIriContentVm: philIriContentVm,
    philIriVm: philIriVm,
    aralVm: aralVm,
    aralClassVm: aralClassVm,
    aralSessionVm: aralSessionVm,
    aralIripVm: aralIripVm,
    aralCheckinVm: aralCheckinVm,
    aralMaterialVm: aralMaterialVm,
    aralReadabilityVm: aralReadabilityVm,
    calendarVm: calendarVm,
    reportSettingsVm: reportSettingsVm,
    nlaReportVm: nlaReportVm,
    reminderVm: reminderVm,
    trendVm: trendVm,
    srpVm: srpVm,
    dashboardVm: dashboardVm,
  );
}

void registerTutorCommands(AppContext ctx, SharedVms s, TutorVms t) {
  final r = ctx.registry;
  final authVm = ctx.authVm;
  registerCrlaCommands(r, authVm, t.crlaVm);
  registerCrlaExportCommands(r, authVm, t.crlaExportVm);
  registerCrlaThresholdCommands(r, t.crlaThresholdVm);
  registerPhilIriContentCommands(r, t.philIriContentVm);
  registerPhilIriCommands(r, t.philIriVm);
  registerAralCommands(r, t.aralVm);
  registerAralClassCommands(r, t.aralClassVm, t.aralVm);
  registerAralSessionCommands(r, t.aralSessionVm);
  registerAralIripCommands(r, t.aralIripVm);
  registerAralCheckinCommands(r, t.aralCheckinVm);
  registerAralMaterialCommands(r, t.aralMaterialVm, t.aralVm);
  registerAralReadabilityCommands(r, t.aralReadabilityVm);
  registerCalendarCommands(r, t.calendarVm);
  registerReminderCommands(r, t.reminderVm, () => authVm.currentUser?.id);
  registerTrendCommands(r, t.trendVm);
  registerSrpCommands(r, t.srpVm);
  registerDashboardCommands(r, t.dashboardVm);
}
