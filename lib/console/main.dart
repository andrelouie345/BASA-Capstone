// lib/console/main.dart
import 'dart:convert';
import 'dart:io';
import 'package:basa_capstone/core/data/remote/student_repository_supabase.dart';
import 'package:basa_capstone/core/data/remote/import_conflict_repository_supabase.dart';
import 'package:basa_capstone/viewmodels/import_viewmodel.dart';
import 'package:basa_capstone/viewmodels/student_viewmodel.dart';
import 'package:basa_capstone/core/data/remote/school_repository_supabase.dart';
import 'package:basa_capstone/core/data/remote/section_repository_supabase.dart';
import 'package:basa_capstone/core/data/remote/tutor_section_assignment_repository_supabase.dart';
import 'package:basa_capstone/core/data/local/tutor_section_assignment_repository_sqlite.dart';
import 'package:basa_capstone/viewmodels/school_viewmodel.dart';
import 'package:basa_capstone/viewmodels/section_viewmodel.dart';
import 'package:basa_capstone/viewmodels/tutor_section_assignment_viewmodel.dart';
import 'package:basa_capstone/core/console/commands/auth_commands.dart';
import 'package:basa_capstone/core/console/commands/config_commands.dart';
import 'package:basa_capstone/core/console/commands/section-commands.dart';
import 'package:basa_capstone/core/console/commands/student_commands.dart';
import 'package:basa_capstone/core/console/commands/admin_bootstrap_commands.dart';
import 'package:basa_capstone/core/console/commands/tutor_section_commands.dart';
import 'package:basa_capstone/core/console/commands/user_commands.dart';
import 'package:basa_capstone/core/console/commands/school_commands.dart';
// import 'package:basa_capstone/core/data/local/import_conflict_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/school_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/section_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/student_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/login_log_repository_sqlite.dart';
// import 'package:basa_capstone/core/data/remote/auth_session_store.dart';
import 'package:basa_capstone/core/console/commands/import_commands.dart';
import 'package:basa_capstone/core/data/remote/supabase_config.dart';
import 'package:basa_capstone/core/data/remote/user_repository_supabase.dart';
import 'package:basa_capstone/viewmodels/user_viewmodel.dart';
import 'package:basa_capstone/core/services/roster_exporter.dart';
import 'package:basa_capstone/core/services/sf1_column_map.dart';
// import 'package:basa_capstone/core/services/sf1_importer.dart';
import 'package:basa_capstone/viewmodels/auth_viewmodel.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common/sqflite.dart';
import '../core/data/local/local_database.dart';
import '../core/data/local/test_repository_sqlite.dart';
import '../core/console/console_registry.dart';
import '../core/console/console_session.dart';
import '../core/console/commands/login_commands.dart';
import '../core/console/commands/text_commands.dart';
import '../core/console/commands/debug_commands.dart';
import '../core/console/commands/test_data_commands.dart';
import '../core/viewmodels/viewmodel_registry.dart';
import '../viewmodels/text_viewmodel.dart';
import '../viewmodels/test_data_viewmodel.dart';
import '../viewmodels/login_log_viewmodel.dart';
import 'package:basa_capstone/core/console/commands/crla_commands.dart';
import 'package:basa_capstone/core/console/commands/crla_import_commands.dart';
import 'package:basa_capstone/viewmodels/crla_import_viewmodel.dart';
import 'package:basa_capstone/viewmodels/crla_export_viewmodel.dart';
import 'package:basa_capstone/core/data/local/crla_assessment_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/crla_part1_english_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/crla_part1_standard_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/crla_part2_fluency_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/crla_result_repository_sqlite.dart';
import 'package:basa_capstone/viewmodels/crla_viewmodel.dart';
import 'package:basa_capstone/core/console/commands/pull_commands.dart';
import 'package:basa_capstone/core/data/local/crla_story_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/crla_threshold_repository_sqlite.dart';
import 'package:basa_capstone/core/console/commands/crla_threshold_commands.dart';
import 'package:basa_capstone/core/data/remote/crla_assessment_repository_supabase.dart';
import 'package:basa_capstone/core/data/remote/crla_part1_english_repository_supabase.dart';
import 'package:basa_capstone/core/data/remote/crla_part1_standard_repository_supabase.dart';
import 'package:basa_capstone/core/data/remote/crla_threshold_repository_supabase.dart';
import 'package:basa_capstone/viewmodels/crla_threshold_viewmodel.dart';
import 'package:basa_capstone/core/console/commands/phil_iri_content_commands.dart';
import 'package:basa_capstone/core/console/commands/phil_iri_commands.dart';
import 'package:basa_capstone/core/console/commands/aral_commands.dart';
import 'package:basa_capstone/core/console/commands/aral_session_commands.dart';
import 'package:basa_capstone/core/console/commands/aral_irip_commands.dart';
import 'package:basa_capstone/core/console/commands/aral_report_commands.dart';
import 'package:basa_capstone/core/console/commands/aral_export_commands.dart';
import 'package:basa_capstone/viewmodels/aral_roster_import_viewmodel.dart';
import 'package:basa_capstone/viewmodels/aral_report_viewmodel.dart';
import 'package:basa_capstone/core/data/local/aral_irip_repository_sqlite.dart';
import 'package:basa_capstone/viewmodels/aral_irip_viewmodel.dart';
import 'package:basa_capstone/core/console/commands/aral_checkin_commands.dart';
import 'package:basa_capstone/core/data/local/aral_checkin_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/aral_setting_repository_sqlite.dart';
import 'package:basa_capstone/core/data/remote/aral_setting_repository_supabase.dart';
import 'package:basa_capstone/viewmodels/aral_checkin_viewmodel.dart';
import 'package:basa_capstone/core/console/commands/aral_material_commands.dart';
import 'package:basa_capstone/core/data/local/aral_material_repository_sqlite.dart';
import 'package:basa_capstone/core/data/remote/aral_material_repository_supabase.dart';
import 'package:basa_capstone/viewmodels/aral_material_viewmodel.dart';
import 'package:basa_capstone/core/console/commands/aral_readability_commands.dart';
import 'package:basa_capstone/core/data/local/aral_readability_repository_sqlite.dart';
import 'package:basa_capstone/viewmodels/aral_readability_viewmodel.dart';
import 'package:basa_capstone/core/console/commands/nla_report_commands.dart';
import 'package:basa_capstone/viewmodels/nla_report_viewmodel.dart';
import 'package:basa_capstone/core/console/commands/srp_commands.dart';
import 'package:basa_capstone/viewmodels/srp_viewmodel.dart';
import 'package:basa_capstone/core/data/local/srp_class_repository_sqlite.dart';
import 'package:basa_capstone/core/data/remote/srp_class_repository_supabase.dart';
import 'package:basa_capstone/core/console/commands/calendar_commands.dart';
import 'package:basa_capstone/viewmodels/round_calendar_viewmodel.dart';
import 'package:basa_capstone/core/data/local/assessment_calendar_repository_sqlite.dart';
import 'package:basa_capstone/core/data/remote/assessment_calendar_repository_supabase.dart';
import 'package:basa_capstone/core/console/commands/report_settings_commands.dart';
import 'package:basa_capstone/viewmodels/report_settings_viewmodel.dart';
import 'package:basa_capstone/viewmodels/reminder_viewmodel.dart';
import 'package:basa_capstone/core/console/commands/reminder_commands.dart';
import 'package:basa_capstone/viewmodels/trend_viewmodel.dart';
import 'package:basa_capstone/core/console/commands/trend_commands.dart';
import 'package:basa_capstone/core/data/local/report_setting_repository_sqlite.dart';
import 'package:basa_capstone/core/data/remote/report_setting_repository_supabase.dart';
import 'package:basa_capstone/core/data/local/aral_session_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/aral_tutor_setting_repository_sqlite.dart';
import 'package:basa_capstone/viewmodels/aral_session_viewmodel.dart';
import 'package:basa_capstone/core/data/local/aral_enrollment_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/user_repository_sqlite.dart';
import 'package:basa_capstone/viewmodels/aral_viewmodel.dart';
import 'package:basa_capstone/core/data/local/phil_iri_assessment_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/phil_iri_collection_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/phil_iri_gst_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/phil_iri_passage_repository_sqlite.dart';
import 'package:basa_capstone/core/data/local/phil_iri_threshold_repository_sqlite.dart';
import 'package:basa_capstone/core/data/remote/phil_iri_collection_repository_supabase.dart';
import 'package:basa_capstone/core/data/remote/phil_iri_passage_repository_supabase.dart';
import 'package:basa_capstone/core/data/remote/phil_iri_threshold_repository_supabase.dart';
import 'package:basa_capstone/viewmodels/phil_iri_content_viewmodel.dart';
import 'package:basa_capstone/viewmodels/phil_iri_viewmodel.dart';

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
  // final conflictRepo = ImportConflictRepositorySqlite(localDb);
  final loginLogRepo = LoginLogRepositorySqlite(localDb);
  
  // final importer = Sf1Importer(
  //   schoolRepo: schoolRepo, sectionRepo: sectionRepo,
  //   studentRepo: studentRepo, conflictRepo: conflictRepo, logger: session,
  // );
  final exporter = RosterExporter();
  final columnMap = await Sf1ColumnMap.load(dir.path);

  final config = await SupabaseConfigStore.load(dir.path);
  registerAdminBootstrapCommands(registry, config, session);
  registerConfigCommands(registry, config);
  registerTestDataCommands(registry, testDataVm, localDb, config);
  
  final authVm = AuthViewModel(
  loginLogRepo: LoginLogRepositorySqlite(localDb),
  config: config,
  userRepoFactory: (client) => UserRepositorySupabase(client),
  logger: session,
  );
  registerAuthCommands(registry, authVm);
  final userVm = UserViewModel(auth: authVm, repoFactory: UserRepositorySupabase.new, logger: session);
  vmRegistry.register('UserViewModel', userVm);
  registerUserCommands(registry, userVm);

  final importVm = ImportViewModel(
    auth: authVm,
    cloudFactory: (client) => ImportCloudRepos(
      schools: SchoolRepositorySupabase(client),
      sections: SectionRepositorySupabase(client),
      students: StudentRepositorySupabase(client),
      conflicts: ImportConflictRepositorySupabase(client),
    ),
    localSchools: schoolRepo,
    localSections: sectionRepo,
    localStudents: studentRepo,
    columnMap: columnMap,
    logger: session,
  );
  vmRegistry.register('ImportViewModel', importVm);
  registerImportCommands(registry, importVm);
  final studentVm = StudentViewModel(auth: authVm, repoFactory: StudentRepositorySupabase.new, logger: session);
  vmRegistry.register('StudentViewModel', studentVm);
  registerStudentCommands(registry, exporter, sectionRepo, studentRepo, studentVm);

  final schoolVm = SchoolViewModel(auth: authVm, repoFactory: SchoolRepositorySupabase.new, logger: session);
  vmRegistry.register('SchoolViewModel', schoolVm);
  registerSchoolCommands(registry, schoolVm);
  final sectionVm = SectionViewModel(auth: authVm, repoFactory: SectionRepositorySupabase.new, logger: session);
  vmRegistry.register('SectionViewModel', sectionVm);
  registerSectionCommands(registry, sectionVm);
  final tutorSectionRepo = TutorSectionAssignmentRepositorySqlite(localDb);
  final tutorSectionVm = TutorSectionAssignmentViewModel(
    auth: authVm,
    repoFactory: TutorSectionAssignmentRepositorySupabase.new,
    local: tutorSectionRepo,
    logger: session,
  );
  vmRegistry.register('TutorSectionAssignmentViewModel', tutorSectionVm);
  registerTutorSectionCommands(registry, tutorSectionVm);

  registerPullCommands(registry, authVm, localDb);

  final loginLogVm = LoginLogViewModel(repo: loginLogRepo, logger: session);
  vmRegistry.register('LoginLogViewModel', loginLogVm);
  registerLoginCommands(registry, loginLogVm, authVm);
    final crlaVm = CrlaViewModel(
    stories: CrlaStoryRepositorySqlite(localDb),
    assessments: CrlaAssessmentRepositorySqlite(localDb),
    part1Standard: CrlaPart1StandardRepositorySqlite(localDb),
    part1English: CrlaPart1EnglishRepositorySqlite(localDb),
    part2Fluency: CrlaPart2FluencyRepositorySqlite(localDb),
    results: CrlaResultRepositorySqlite(localDb),
    sections: SectionRepositorySqlite(localDb),
    schools: SchoolRepositorySqlite(localDb),
    thresholds: CrlaThresholdRepositorySqlite(localDb),
    logger: session,
  );
  vmRegistry.register('CrlaViewModel', crlaVm);
  registerCrlaCommands(registry, authVm, crlaVm);
  final crlaImportVm = CrlaImportViewModel(
    auth: authVm,
    crla: crlaVm,
    assessments: CrlaAssessmentRepositorySqlite(localDb),
    sections: SectionRepositorySqlite(localDb),
    students: StudentRepositorySqlite(localDb),
    logger: session,
  );
  vmRegistry.register('CrlaImportViewModel', crlaImportVm);
  registerCrlaImportCommands(registry, authVm, crlaImportVm);
  final crlaExportVm = CrlaExportViewModel(
    auth: authVm,
    sections: SectionRepositorySqlite(localDb),
    schools: SchoolRepositorySqlite(localDb),
    students: StudentRepositorySqlite(localDb),
    assessments: CrlaAssessmentRepositorySqlite(localDb),
    part1Standard: CrlaPart1StandardRepositorySqlite(localDb),
    part1English: CrlaPart1EnglishRepositorySqlite(localDb),
    part2Fluency: CrlaPart2FluencyRepositorySqlite(localDb),
    stories: CrlaStoryRepositorySqlite(localDb),
    thresholds: CrlaThresholdRepositorySqlite(localDb),
    logger: session,
  );
  vmRegistry.register('CrlaExportViewModel', crlaExportVm);
  registerCrlaExportCommands(registry, authVm, crlaExportVm);
  // CRLA thresholds are managed online (mirrored locally); regenerate runs in the cloud.
  final crlaThresholdVm = CrlaThresholdViewModel(
    auth: authVm,
    cloudFactory: (client) => CrlaThresholdCloudRepos(
      thresholds: CrlaThresholdRepositorySupabase(client),
      assessments: CrlaAssessmentRepositorySupabase(client),
      part1Standard: CrlaPart1StandardRepositorySupabase(client),
      part1English: CrlaPart1EnglishRepositorySupabase(client),
    ),
    localThresholds: CrlaThresholdRepositorySqlite(localDb),
    localAssessments: CrlaAssessmentRepositorySqlite(localDb),
    localPart1Standard: CrlaPart1StandardRepositorySqlite(localDb),
    localPart1English: CrlaPart1EnglishRepositorySqlite(localDb),
    logger: session,
  );
  vmRegistry.register('CrlaThresholdViewModel', crlaThresholdVm);
  registerCrlaThresholdCommands(registry, crlaThresholdVm);

  // Phil-IRI: content is managed online (mirrored locally); assessments are local.
  final philIriContentVm = PhilIriContentViewModel(
    auth: authVm,
    cloudFactory: (client) => PhilIriContentCloudRepos(
      collections: PhilIriCollectionRepositorySupabase(client),
      passages: PhilIriPassageRepositorySupabase(client),
      thresholds: PhilIriThresholdRepositorySupabase(client),
    ),
    localCollections: PhilIriCollectionRepositorySqlite(localDb),
    localPassages: PhilIriPassageRepositorySqlite(localDb),
    localThresholds: PhilIriThresholdRepositorySqlite(localDb),
    logger: session,
  );
  vmRegistry.register('PhilIriContentViewModel', philIriContentVm);
  registerPhilIriContentCommands(registry, philIriContentVm);
  final philIriVm = PhilIriViewModel(
    auth: authVm,
    sessions: PhilIriAssessmentRepositorySqlite(localDb),
    gst: PhilIriGstRepositorySqlite(localDb),
    passages: PhilIriPassageRepositorySqlite(localDb),
    collections: PhilIriCollectionRepositorySqlite(localDb),
    thresholds: PhilIriThresholdRepositorySqlite(localDb),
    sections: SectionRepositorySqlite(localDb),
    logger: session,
  );
  vmRegistry.register('PhilIriViewModel', philIriVm);
  registerPhilIriCommands(registry, philIriVm);

  final aralVm = AralViewModel(
    auth: authVm,
    roster: AralEnrollmentRepositorySqlite(localDb),
    sections: SectionRepositorySqlite(localDb),
    students: StudentRepositorySqlite(localDb),
    users: UserRepositorySqlite(localDb),
    crlaResults: CrlaResultRepositorySqlite(localDb),
    philIri: philIriVm,
    localSettings: AralSettingRepositorySqlite(localDb),
    logger: session,
  );
  vmRegistry.register('AralViewModel', aralVm);
  registerAralCommands(registry, aralVm);

  final aralSessionVm = AralSessionViewModel(
    auth: authVm,
    sessions: AralSessionRepositorySqlite(localDb),
    roster: AralEnrollmentRepositorySqlite(localDb),
    users: UserRepositorySqlite(localDb),
    students: StudentRepositorySqlite(localDb),
    settings: AralTutorSettingRepositorySqlite(localDb),
    logger: session,
  );
  vmRegistry.register('AralSessionViewModel', aralSessionVm);
  registerAralSessionCommands(registry, aralSessionVm);

  final aralIripVm = AralIripViewModel(
    auth: authVm,
    irip: AralIripRepositorySqlite(localDb),
    roster: AralEnrollmentRepositorySqlite(localDb),
    logger: session,
  );
  vmRegistry.register('AralIripViewModel', aralIripVm);
  registerAralIripCommands(registry, aralIripVm);

  // Check-ins are local; the cut-off is set online and mirrored locally.
  final aralCheckinVm = AralCheckinViewModel(
    auth: authVm,
    checkins: AralCheckinRepositorySqlite(localDb),
    roster: AralEnrollmentRepositorySqlite(localDb),
    localSettings: AralSettingRepositorySqlite(localDb),
    cloudSettings: (client) => AralSettingRepositorySupabase(client),
    sections: SectionRepositorySqlite(localDb),
    students: StudentRepositorySqlite(localDb),
    logger: session,
  );
  vmRegistry.register('AralCheckinViewModel', aralCheckinVm);
  registerAralCheckinCommands(registry, aralCheckinVm);

  final aralMaterialVm = AralMaterialViewModel(
    auth: authVm,
    local: AralMaterialRepositorySqlite(localDb),
    cloud: (client) => AralMaterialRepositorySupabase(client),
    roster: AralEnrollmentRepositorySqlite(localDb),
    sections: SectionRepositorySqlite(localDb),
    localSettings: AralSettingRepositorySqlite(localDb),
    logger: session,
  );
  vmRegistry.register('AralMaterialViewModel', aralMaterialVm);
  registerAralMaterialCommands(registry, aralMaterialVm);

  final aralReadabilityVm = AralReadabilityViewModel(
    auth: authVm,
    logs: AralReadabilityRepositorySqlite(localDb),
    roster: AralEnrollmentRepositorySqlite(localDb),
    localSettings: AralSettingRepositorySqlite(localDb),
    materials: AralMaterialRepositorySqlite(localDb),
    logger: session,
  );
  vmRegistry.register('AralReadabilityViewModel', aralReadabilityVm);
  registerAralReadabilityCommands(registry, aralReadabilityVm);

  final calendarVm = RoundCalendarViewModel(
    auth: authVm,
    local: AssessmentCalendarRepositorySqlite(localDb),
    cloud: (client) => AssessmentCalendarRepositorySupabase(client),
    logger: session,
  );
  vmRegistry.register('RoundCalendarViewModel', calendarVm);
  registerCalendarCommands(registry, calendarVm);

  final reportSettingsVm = ReportSettingsViewModel(
    auth: authVm,
    local: ReportSettingRepositorySqlite(localDb),
    cloud: (client) => ReportSettingRepositorySupabase(client),
    logger: session,
  );
  vmRegistry.register('ReportSettingsViewModel', reportSettingsVm);
  registerReportSettingsCommands(registry, reportSettingsVm);

  final nlaReportVm = NlaReportViewModel(
    auth: authVm,
    sections: SectionRepositorySqlite(localDb),
    students: StudentRepositorySqlite(localDb),
    philIri: philIriVm,
    reportSettings: reportSettingsVm,
    calendar: calendarVm,
    logger: session,
  );
  vmRegistry.register('NlaReportViewModel', nlaReportVm);
  registerNlaReportCommands(registry, nlaReportVm);

  final reminderVm = ReminderViewModel(
    auth: authVm,
    calendar: calendarVm,
    reports: nlaReportVm,
    reportSettings: reportSettingsVm,
    schools: SchoolRepositorySqlite(localDb),
    sections: SectionRepositorySqlite(localDb),
    students: StudentRepositorySqlite(localDb),
    crlaResults: CrlaResultRepositorySqlite(localDb),
    assignments: tutorSectionRepo,
    users: UserRepositorySqlite(localDb),
    roster: AralEnrollmentRepositorySqlite(localDb),
    aralSessions: AralSessionRepositorySqlite(localDb),
    irip: AralIripRepositorySqlite(localDb),
    checkins: AralCheckinRepositorySqlite(localDb),
    aralSettings: AralSettingRepositorySqlite(localDb),
    logger: session,
  );
  vmRegistry.register('ReminderViewModel', reminderVm);
  registerReminderCommands(registry, reminderVm, () => authVm.currentUser?.id);

  final trendVm = TrendViewModel(
    auth: authVm,
    schools: SchoolRepositorySqlite(localDb),
    sections: SectionRepositorySqlite(localDb),
    students: StudentRepositorySqlite(localDb),
    users: UserRepositorySqlite(localDb),
    crlaResults: CrlaResultRepositorySqlite(localDb),
    nla: nlaReportVm,
    aral: aralSessionVm,
    aralSessions: AralSessionRepositorySqlite(localDb),
    logger: session,
  );
  vmRegistry.register('TrendViewModel', trendVm);
  registerTrendCommands(registry, trendVm);

  final srpVm = SrpViewModel(
    reports: nlaReportVm,
    students: StudentRepositorySqlite(localDb),
    philIri: philIriVm,
    auth: authVm,
    local: SrpClassRepositorySqlite(localDb),
    cloud: (client) => SrpClassRepositorySupabase(client),
    users: UserRepositorySqlite(localDb),
    sections: SectionRepositorySqlite(localDb),
    logger: session,
  );
  vmRegistry.register('SrpViewModel', srpVm);
  registerSrpCommands(registry, srpVm);

  final aralReportVm = AralReportViewModel(
    auth: authVm,
    roster: AralEnrollmentRepositorySqlite(localDb),
    sections: SectionRepositorySqlite(localDb),
    students: StudentRepositorySqlite(localDb),
    crlaResults: CrlaResultRepositorySqlite(localDb),
    philIri: philIriVm,
    logger: session,
  );
  vmRegistry.register('AralReportViewModel', aralReportVm);
  registerAralReportCommands(registry, aralReportVm);
  registerAralExportCommands(registry, aralVm, aralReportVm, aralCheckinVm);
  final aralRosterImportVm = AralRosterImportViewModel(
    auth: authVm,
    aral: aralVm,
    roster: AralEnrollmentRepositorySqlite(localDb),
    sections: SectionRepositorySqlite(localDb),
    students: StudentRepositorySqlite(localDb),
    users: UserRepositorySqlite(localDb),
    logger: session,
  );
  vmRegistry.register('AralRosterImportViewModel', aralRosterImportVm);
  registerAralRosterImportCommands(registry, aralRosterImportVm);
  registerDebugCommands(registry, session, vmRegistry);

  // Headless REPL: lets the console run from a terminal or a piped script.
  stdout.writeln('BASA console ready. Type "help", or "exit" to quit.');
  var printed = session.entries.length;
  while (true) {
    stdout.write('> ');
    final line = stdin.readLineSync(encoding: utf8); // not the Windows codepage
    if (line == null || line.trim() == 'exit') break; // null = end of piped input
    await session.run(line);
    for (final e in session.entries.skip(printed)) {
      if (e.type == ConsoleEntryType.input) continue;
      stdout.writeln(e.type == ConsoleEntryType.log ? '[${e.source}] ${e.message}' : e.message);
    }
    printed = session.entries.length;
  }
  exit(0); // the Supabase client can keep the process alive otherwise
}