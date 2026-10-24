// lib/viewmodels/app_viewmodels.dart
// What a screen gets (both builds): every ViewModel a tutor-build screen may
// call, and nothing else. No repositories, no services, no dev-only
// ViewModels (text, testTable), so a screen cannot go around a ViewModel.
// Built in core/wiring (appViewModels) and handed to the widget tree by
// ui/basa_scope.dart: `BasaScope.of(context).crla`. Admin-only ViewModels are
// in admin_viewmodels.dart (admin build only).
import 'aral_checkin_viewmodel.dart';
import 'aral_class_viewmodel.dart';
import 'aral_irip_viewmodel.dart';
import 'aral_material_viewmodel.dart';
import 'aral_readability_viewmodel.dart';
import 'aral_session_viewmodel.dart';
import 'aral_viewmodel.dart';
import 'auth_viewmodel.dart';
import 'crla_export_viewmodel.dart';
import 'crla_threshold_viewmodel.dart';
import 'crla_viewmodel.dart';
import 'dashboard_viewmodel.dart';
import 'nla_report_viewmodel.dart';
import 'phil_iri_content_viewmodel.dart';
import 'phil_iri_viewmodel.dart';
import 'reminder_viewmodel.dart';
import 'report_settings_viewmodel.dart';
import 'round_calendar_viewmodel.dart';
import 'school_viewmodel.dart';
import 'section_viewmodel.dart';
import 'server_config_viewmodel.dart';
import 'srp_viewmodel.dart';
import 'student_viewmodel.dart';
import 'sync_viewmodel.dart';
import 'trend_viewmodel.dart';

class AppViewModels {
  // Account, server, sync, lists
  final AuthViewModel auth;
  final ServerConfigViewModel serverConfig;
  final SyncViewModel sync;
  final SchoolViewModel school;
  final SectionViewModel section;
  final StudentViewModel student;

  // CRLA
  final CrlaViewModel crla;
  final CrlaExportViewModel crlaExport;
  final CrlaThresholdViewModel crlaThresholds;

  // Phil-IRI
  final PhilIriViewModel philIri;
  final PhilIriContentViewModel philIriContent;

  // ARAL
  final AralViewModel aral;
  final AralClassViewModel aralClass;
  final AralSessionViewModel aralSession;
  final AralIripViewModel aralIrip;
  final AralCheckinViewModel aralCheckin;
  final AralMaterialViewModel aralMaterial;
  final AralReadabilityViewModel aralReadability;

  // Dashboard and reports (several methods refuse tutors; see docs/handoff/screens/)
  final RoundCalendarViewModel calendar;
  final ReportSettingsViewModel reportSettings;
  final NlaReportViewModel nlaReport;
  final ReminderViewModel reminders;
  final TrendViewModel trend;
  final SrpViewModel srp;
  final DashboardViewModel dashboard;

  AppViewModels({
    required this.auth,
    required this.serverConfig,
    required this.sync,
    required this.school,
    required this.section,
    required this.student,
    required this.crla,
    required this.crlaExport,
    required this.crlaThresholds,
    required this.philIri,
    required this.philIriContent,
    required this.aral,
    required this.aralClass,
    required this.aralSession,
    required this.aralIrip,
    required this.aralCheckin,
    required this.aralMaterial,
    required this.aralReadability,
    required this.calendar,
    required this.reportSettings,
    required this.nlaReport,
    required this.reminders,
    required this.trend,
    required this.srp,
    required this.dashboard,
  });
}
