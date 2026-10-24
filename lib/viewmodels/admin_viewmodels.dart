// lib/viewmodels/admin_viewmodels.dart
// What an admin-build screen gets on top of AppViewModels: the admin-only
// ViewModels. Admin build only: never reachable from the tutor entry points
// (tool/check_tutor_imports.dart). Built in core/wiring (adminViewModels) and
// handed to the widget tree by ui/admin/admin_scope.dart:
// `AdminScope.of(context).users`.
import 'admin_bootstrap_viewmodel.dart';
import 'aral_report_viewmodel.dart';
import 'aral_roster_import_viewmodel.dart';
import 'crla_import_viewmodel.dart';
import 'import_viewmodel.dart';
import 'login_log_viewmodel.dart';
import 'sync_review_viewmodel.dart';
import 'tutor_section_assignment_viewmodel.dart';
import 'user_viewmodel.dart';

class AdminViewModels {
  final AdminBootstrapViewModel bootstrap;
  final UserViewModel users;
  final TutorSectionAssignmentViewModel tutorSections;
  final LoginLogViewModel loginLogs;
  final SyncReviewViewModel syncReview;

  /// SF1 import.
  final ImportViewModel sf1Import;
  final CrlaImportViewModel crlaImport;
  final AralRosterImportViewModel aralRosterImport;
  final AralReportViewModel aralReport;

  AdminViewModels({
    required this.bootstrap,
    required this.users,
    required this.tutorSections,
    required this.loginLogs,
    required this.syncReview,
    required this.sf1Import,
    required this.crlaImport,
    required this.aralRosterImport,
    required this.aralReport,
  });
}
