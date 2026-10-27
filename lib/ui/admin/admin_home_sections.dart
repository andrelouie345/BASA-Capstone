// lib/ui/admin/admin_home_sections.dart
// The admin build's navigation: every section both builds have (their
// screens with the admin parts: editors), the admin screens added to them,
// and two sections of its own (Manage, Reports).
// lib/main.dart hands it to BasaApp; the tutor build never sees it.
import 'package:flutter/material.dart';

import '../aral/aral_settings_screen.dart';
import '../aral/classes_screen.dart';
import '../aral/materials_screen.dart';
import '../aral/roster_screen.dart';
import '../crla/crla_thresholds_screen.dart';
import '../dashboard/calendar_screen.dart';
import '../home/home_sections.dart';
import '../learners/learners_screen.dart';
import '../learners/schools_screen.dart';
import '../learners/sections_screen.dart';
import '../phil_iri/content_screen.dart';
import '../phil_iri/phil_iri_thresholds_screen.dart';
import '../reports/srp_screen.dart';
import 'aral_editing.dart';
import 'aral_report_screen.dart';
import 'calendar_editing.dart';
import 'crla_import_screen.dart';
import 'crla_threshold_editing.dart';
import 'first_admin_screen.dart';
import 'learner_history_screen.dart';
import 'login_logs_screen.dart';
import 'phil_iri_content_editing.dart';
import 'phil_iri_finalize_screen.dart';
import 'phil_iri_threshold_editing.dart';
import 'report_screens.dart';
import 'reports_hub_screen.dart';
import 'school_editing.dart';
import 'section_editing.dart';
import 'sf1_import_screen.dart';
import 'srp_editing.dart';
import 'sync_review_screen.dart';
import 'tutor_assignments_screen.dart';
import 'users_screen.dart';

List<HomeSection> adminHomeSections() => [
  for (final s in basaHomeSections().map((s) => s.withBuilders(_adminVersions)))
    switch (s.id) {
      HomeSectionIds.assess => s
          .adding('CRLA (Grades 1–3)', const [
            HomeEntry(
              title: 'Scoresheet import',
              description: 'Read CRLA scoresheets into BASA',
              icon: Icons.file_upload_outlined,
              checklistRow: 26,
              doc: 'crla.md#scoresheet-import',
              builder: _row26,
            ),
          ])
          .adding('Phil-IRI (Grades 4–10)', const [
            HomeEntry(
              title: 'Finalize',
              description: "Close a round's Phil-IRI results",
              icon: Icons.task_alt,
              checklistRow: 31,
              doc: 'phil-iri.md#finalize',
              builder: _row31,
            ),
          ]),
      HomeSectionIds.sync => s.adding('Approvals', const [
        HomeEntry(
          title: 'Review uploads',
          description: "Approve or reject tutors' uploads",
          icon: Icons.approval_outlined,
          checklistRow: 56,
          doc: 'sync.md#review-uploads-approver',
          builder: _row56,
        ),
      ]),
      _ => s,
    },
  const HomeSection(
    id: 'manage',
    label: 'Manage',
    icon: Icons.admin_panel_settings_outlined,
    selectedIcon: Icons.admin_panel_settings,
    groups: [
      HomeGroup('People', [
        HomeEntry(
          title: 'Users',
          description: 'Accounts, roles and access',
          icon: Icons.manage_accounts_outlined,
          checklistRow: 12,
          doc: 'admin.md#users',
          builder: _row12,
        ),
        HomeEntry(
          title: 'Tutor assignments',
          description: 'Which sections each tutor has',
          icon: Icons.assignment_turned_in_outlined,
          checklistRow: 13,
          doc: 'admin.md#tutor-assignments',
          builder: _row13,
        ),
        HomeEntry(
          title: 'Login logs',
          description: 'Who signed in, and when',
          icon: Icons.history,
          checklistRow: 19,
          doc: 'admin.md#login-logs',
          builder: _row19,
        ),
        HomeEntry(
          title: 'First admin',
          description: 'Create the first admin of a new server',
          icon: Icons.vpn_key_outlined,
          checklistRow: 20,
          doc: 'admin.md#first-admin-bootstrap',
          builder: _row20,
        ),
      ]),
      HomeGroup('Learners', [
        HomeEntry(
          title: 'SF1 import',
          description: 'Bring in learners from a school form 1',
          icon: Icons.upload_file_outlined,
          checklistRow: 18,
          doc: 'admin.md#sf1-import',
          builder: _row18,
        ),
        HomeEntry(
          title: 'Learner history',
          description: "One learner's progress by school year",
          icon: Icons.timeline_outlined,
          checklistRow: 17,
          doc: 'admin.md#learner-history',
          builder: _row17,
        ),
      ]),
      HomeGroup('Settings', [
        HomeEntry(
          title: 'Report settings',
          description: 'Done threshold, auto-approve, offline days',
          icon: Icons.rule_outlined,
          checklistRow: 48,
          doc: 'reports.md#report-settings-done-threshold-auto-approve-offline-days',
          builder: _row48,
        ),
      ]),
    ],
  ),
  const HomeSection(
    id: 'reports',
    label: 'Reports',
    icon: Icons.summarize_outlined,
    selectedIcon: Icons.summarize,
    groups: [
      HomeGroup('Reports', [
        HomeEntry(
          title: 'Reports & files',
          description: 'Every report and file in one place',
          icon: Icons.folder_copy_outlined,
          checklistRow: 49,
          doc: 'reports.md#reports--files-hub',
          builder: _row49,
        ),
        HomeEntry(
          title: 'NLA portal report',
          description: 'Phil-IRI JHS Form 2b and the Division ARAL report',
          icon: Icons.assessment_outlined,
          checklistRow: 44,
          doc: 'reports.md#nla-portal-report-phil-iri-jhs-form-2b--division-aral',
          builder: _row44,
        ),
        HomeEntry(
          title: 'Progress monitoring',
          description: 'How far each section is in each round',
          icon: Icons.donut_large_outlined,
          checklistRow: 45,
          doc: 'reports.md#progress-monitoring',
          builder: _row45,
        ),
        HomeEntry(
          title: 'BOSY masterlist',
          description: 'Learners not grade level ready',
          icon: Icons.format_list_numbered,
          checklistRow: 46,
          doc: 'reports.md#bosy-masterlist',
          builder: _row46,
        ),
        HomeEntry(
          title: 'ARAL implementation report',
          description: 'The report and the roster files',
          icon: Icons.description_outlined,
          checklistRow: 43,
          doc: 'aral.md#implementation-report-and-roster-files',
          builder: _row43,
        ),
      ]),
    ],
  ),
];

/// Shared screens opened with their admin parts (checklist row → screen).
final Map<int, WidgetBuilder> _adminVersions = {
  14: (_) => const SchoolsScreen(editor: AdminSchoolsEditor()),
  15: (_) => const SectionsScreen(editor: AdminSectionsEditor()),
  16: (_) => LearnersScreen(
    onOpenLearner: (context, s) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => LearnerHistoryScreen(studentId: s.id))),
  ),
  24: (_) => const CrlaThresholdsScreen(editor: AdminCrlaThresholdsEditor()),
  32: (_) => const PhilIriContentScreen(editor: AdminPhilIriContentEditor()),
  33: (_) => const PhilIriThresholdsScreen(editor: AdminPhilIriThresholdsEditor()),
  34: (_) => const AralRosterScreen(editor: AdminAralRosterEditor()),
  36: (_) => const AralClassesScreen(editor: AdminAralClassEditor()),
  40: (_) => const AralSettingsScreen(editor: AdminAralSettingsEditor()),
  41: (_) => const AralMaterialsScreen(editor: AdminAralMaterialsEditor()),
  47: (_) => const SrpScreen(editor: AdminSrpEditor()),
  51: (_) => const CalendarScreen(editor: AdminCalendarEditor()),
};

// The admin-only screens (const entries need top-level functions).
Widget _row26(BuildContext _) => const CrlaImportScreen();
Widget _row31(BuildContext _) => const PhilIriFinalizeScreen();
Widget _row56(BuildContext _) => const SyncReviewScreen();
Widget _row12(BuildContext _) => const UsersScreen();
Widget _row13(BuildContext _) => const TutorAssignmentsScreen();
Widget _row19(BuildContext _) => const LoginLogsScreen();
Widget _row18(BuildContext _) => const Sf1ImportScreen();
Widget _row17(BuildContext _) => const LearnerHistoryScreen();
Widget _row48(BuildContext _) => const ReportSettingsScreen();
Widget _row49(BuildContext _) => const ReportsHubScreen();
Widget _row44(BuildContext _) => const NlaReportScreen();
Widget _row45(BuildContext _) => const ProgressScreen();
Widget _row46(BuildContext _) => const BosyMasterlistScreen();
Widget _row43(BuildContext _) => const AralReportScreen();
Widget _row20(BuildContext _) => const FirstAdminScreen();
