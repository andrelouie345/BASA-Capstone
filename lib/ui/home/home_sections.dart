// lib/ui/home/home_sections.dart
// What the home screen's navigation offers: sections (the rail / bottom bar),
// each with groups of entries (one per screen in docs/handoff/checklist.md).
// Both builds start from basaHomeSections(); the admin build adds its own in
// lib/ui/admin/admin_home_sections.dart, so nothing here imports an admin file.
//
// Each entry's `builder` opens its screen; an entry without one opens
// NotBuiltScreen ("coming soon"). The admin build swaps in screens with their
// admin parts (withBuilders) and adds its own entries.
import 'package:flutter/material.dart';

import '../aral/aral_settings_screen.dart';
import '../aral/classes_screen.dart';
import '../aral/learner_aral_screen.dart';
import '../aral/learner_pick_screen.dart';
import '../aral/materials_screen.dart';
import '../aral/roster_screen.dart';
import '../aral/sessions_screen.dart';
import '../crla/crla_export_screen.dart';
import '../crla/crla_section_screen.dart';
import '../crla/crla_thresholds_screen.dart';
import '../dashboard/calendar_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../dashboard/reminders_screen.dart';
import '../dashboard/trends_screen.dart';
import '../learners/learners_screen.dart';
import '../learners/schools_screen.dart';
import '../learners/sections_screen.dart';
import '../phil_iri/content_screen.dart';
import '../phil_iri/gst_screen.dart';
import '../phil_iri/learner_results_screen.dart';
import '../phil_iri/phil_iri_section_screen.dart';
import '../phil_iri/phil_iri_thresholds_screen.dart';
import '../reports/srp_screen.dart';
import '../sync/pull_screen.dart';
import '../sync/upload_screen.dart';

/// One screen the user can open from a section page.
class HomeEntry {
  final String title;

  /// One line under the title.
  final String description;
  final IconData icon;

  /// Its row in docs/handoff/checklist.md (shown in debug builds while the
  /// screen isn't built).
  final int checklistRow;

  /// Its block in docs/handoff/screens/, e.g. `crla.md#section-crla-list`.
  final String doc;

  /// Builds the screen; null = not built yet.
  final WidgetBuilder? builder;

  const HomeEntry({
    required this.title,
    required this.description,
    required this.icon,
    required this.checklistRow,
    required this.doc,
    this.builder,
  });
}

/// A titled run of entries on a section page.
class HomeGroup {
  final String title;
  final List<HomeEntry> entries;
  const HomeGroup(this.title, this.entries);
}

/// One destination of the navigation rail / bottom bar.
class HomeSection {
  /// Stable name, used to find a section (e.g. the status chip opens `sync`).
  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final List<HomeGroup> groups;

  const HomeSection({
    required this.id,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.groups,
  });

  /// This section with the screens of [builders] (checklist row → builder)
  /// in place of its entries' own.
  HomeSection withBuilders(Map<int, WidgetBuilder> builders) => HomeSection(
    id: id,
    label: label,
    icon: icon,
    selectedIcon: selectedIcon,
    groups: [
      for (final g in groups)
        HomeGroup(g.title, [
          for (final e in g.entries)
            builders.containsKey(e.checklistRow)
                ? HomeEntry(
                    title: e.title,
                    description: e.description,
                    icon: e.icon,
                    checklistRow: e.checklistRow,
                    doc: e.doc,
                    builder: builders[e.checklistRow],
                  )
                : e,
        ]),
    ],
  );

  /// This section with [entries] added to the group titled [group]
  /// (a new group at the end when there is none).
  HomeSection adding(String group, List<HomeEntry> entries) {
    final has = groups.any((g) => g.title == group);
    return HomeSection(
      id: id,
      label: label,
      icon: icon,
      selectedIcon: selectedIcon,
      groups: [
        for (final g in groups) g.title == group ? HomeGroup(g.title, [...g.entries, ...entries]) : g,
        if (!has) HomeGroup(group, entries),
      ],
    );
  }
}

/// Section ids both builds use.
abstract final class HomeSectionIds {
  static const home = 'home';
  static const learners = 'learners';
  static const assess = 'assess';
  static const aral = 'aral';
  static const sync = 'sync';
}

/// The sections every build has, with the screens a tutor can use. Screens
/// that are "both (view) / admin (edit)" are here; their admin parts live in
/// the screen itself (AdminScope only under lib/ui/admin/).
List<HomeSection> basaHomeSections() => const [
  HomeSection(
    id: HomeSectionIds.home,
    label: 'Home',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    groups: [
      HomeGroup('This school year', [
        HomeEntry(
          title: 'Dashboard',
          description: "The year's figures for your work",
          icon: Icons.space_dashboard_outlined,
          checklistRow: 50,
          doc: 'dashboard.md#dashboard-home',
          builder: _row50,
        ),
        HomeEntry(
          title: 'Reminders',
          description: 'Learners to assess, check-ins due, idle classes',
          icon: Icons.notifications_active_outlined,
          checklistRow: 52,
          doc: 'dashboard.md#reminders',
          builder: _row52,
        ),
        HomeEntry(
          title: 'Round calendar',
          description: 'When each assessment round opens and closes',
          icon: Icons.event_outlined,
          checklistRow: 51,
          doc: 'dashboard.md#round-calendar',
          builder: _row51,
        ),
        HomeEntry(
          title: 'Trends',
          description: 'Sessions held and attendance over time',
          icon: Icons.insights_outlined,
          checklistRow: 53,
          doc: 'dashboard.md#trends',
          builder: _row53,
        ),
      ]),
    ],
  ),
  HomeSection(
    id: HomeSectionIds.learners,
    label: 'Learners',
    icon: Icons.groups_outlined,
    selectedIcon: Icons.groups,
    groups: [
      HomeGroup('Schools and sections', [
        HomeEntry(
          title: 'Learners',
          description: 'Learners by section, and the roster CSV',
          icon: Icons.person_search_outlined,
          checklistRow: 16,
          doc: 'admin.md#learners-and-roster-csv',
          builder: _row16,
        ),
        HomeEntry(
          title: 'Sections',
          description: 'Sections by grade and school year',
          icon: Icons.class_outlined,
          checklistRow: 15,
          doc: 'admin.md#sections',
          builder: _row15,
        ),
        HomeEntry(
          title: 'Schools',
          description: 'Schools you can see',
          icon: Icons.school_outlined,
          checklistRow: 14,
          doc: 'admin.md#schools',
          builder: _row14,
        ),
      ]),
    ],
  ),
  HomeSection(
    id: HomeSectionIds.assess,
    label: 'Assess',
    icon: Icons.fact_check_outlined,
    selectedIcon: Icons.fact_check,
    groups: [
      HomeGroup('CRLA (Grades 1–3)', [
        HomeEntry(
          title: 'CRLA by section',
          description: "A section's learners, attempts and results",
          icon: Icons.record_voice_over_outlined,
          checklistRow: 21,
          doc: 'crla.md#section-crla-list',
          builder: _row21,
        ),
        HomeEntry(
          title: 'Scoresheet export',
          description: 'Fill the DepEd CRLA2 template',
          icon: Icons.file_download_outlined,
          checklistRow: 25,
          doc: 'crla.md#scoresheet-export-crla2-template',
          builder: _row25,
        ),
        HomeEntry(
          title: 'CRLA thresholds',
          description: 'The cut-offs behind each reading profile',
          icon: Icons.tune,
          checklistRow: 24,
          doc: 'crla.md#crla-thresholds',
          builder: _row24,
        ),
      ]),
      HomeGroup('Phil-IRI (Grades 4–10)', [
        HomeEntry(
          title: 'Group Screening Test',
          description: 'GST scores for a section',
          icon: Icons.groups_2_outlined,
          checklistRow: 27,
          doc: 'phil-iri.md#gst-group-screening-test',
          builder: _row27,
        ),
        HomeEntry(
          title: 'Phil-IRI by section',
          description: 'Sessions: reading, miscues, answers, rubric',
          icon: Icons.menu_book_outlined,
          checklistRow: 28,
          doc: 'phil-iri.md#section-phil-iri-sessions',
          builder: _row28,
        ),
        HomeEntry(
          title: 'Learner results',
          description: "One learner's Phil-IRI results",
          icon: Icons.assignment_ind_outlined,
          checklistRow: 30,
          doc: 'phil-iri.md#learner-results',
          builder: _row30,
        ),
        HomeEntry(
          title: 'Passages and questions',
          description: 'Collections, passages, questions, rubric',
          icon: Icons.library_books_outlined,
          checklistRow: 32,
          doc: 'phil-iri.md#content-collections-passages-questions-rubric',
          builder: _row32,
        ),
        HomeEntry(
          title: 'Phil-IRI thresholds',
          description: 'The cut-offs behind each reading level',
          icon: Icons.tune,
          checklistRow: 33,
          doc: 'phil-iri.md#phil-iri-thresholds',
          builder: _row33,
        ),
      ]),
    ],
  ),
  HomeSection(
    id: HomeSectionIds.aral,
    label: 'ARAL',
    icon: Icons.auto_stories_outlined,
    selectedIcon: Icons.auto_stories,
    groups: [
      HomeGroup('Classes', [
        HomeEntry(
          title: 'Classes',
          description: 'ARAL classes, their learners and tutor',
          icon: Icons.co_present_outlined,
          checklistRow: 36,
          doc: 'aral.md#classes',
          builder: _row36,
        ),
        HomeEntry(
          title: 'Sessions and attendance',
          description: "Record a class's session and who came",
          icon: Icons.how_to_reg_outlined,
          checklistRow: 37,
          doc: 'aral.md#sessions-and-attendance',
          builder: _row37,
        ),
        HomeEntry(
          title: 'Check-ins',
          description: 'Check-in assessments after sessions 16 and 32',
          icon: Icons.checklist_outlined,
          checklistRow: 39,
          doc: 'aral.md#check-ins',
          builder: _row39,
        ),
        HomeEntry(
          title: 'IRIP',
          description: "Each learner's intervention plan and weeks",
          icon: Icons.flag_outlined,
          checklistRow: 38,
          doc: 'aral.md#irip',
          builder: _row38,
        ),
      ]),
      HomeGroup('Program', [
        HomeEntry(
          title: 'Roster',
          description: 'Who is in ARAL, by section, school or tutor',
          icon: Icons.list_alt_outlined,
          checklistRow: 34,
          doc: 'aral.md#roster-section--school--tutor',
          builder: _row34,
        ),
        HomeEntry(
          title: 'Tutors',
          description: 'ARAL tutors and their classes',
          icon: Icons.badge_outlined,
          checklistRow: 35,
          doc: 'aral.md#tutors',
          builder: _row35,
        ),
        HomeEntry(
          title: 'Materials',
          description: 'Learning materials and recommendations',
          icon: Icons.folder_open_outlined,
          checklistRow: 41,
          doc: 'aral.md#materials-and-recommendations',
          builder: _row41,
        ),
        HomeEntry(
          title: 'Readability log',
          description: 'Flesch scores of texts (SHARP only)',
          icon: Icons.text_snippet_outlined,
          checklistRow: 42,
          doc: 'aral.md#readability-log-sharp-only',
          builder: _row42,
        ),
        HomeEntry(
          title: 'Summer Remediation',
          description: 'SRP classes and their learners',
          icon: Icons.wb_sunny_outlined,
          checklistRow: 47,
          doc: 'reports.md#srp-summer-remediation-program',
          builder: _row47,
        ),
        HomeEntry(
          title: 'ARAL settings',
          description: "The school's ARAL rules",
          icon: Icons.settings_outlined,
          checklistRow: 40,
          doc: 'aral.md#aral-settings',
          builder: _row40,
        ),
      ]),
    ],
  ),
  HomeSection(
    id: HomeSectionIds.sync,
    label: 'Sync',
    icon: Icons.sync_outlined,
    selectedIcon: Icons.sync,
    groups: [
      HomeGroup('This device and the server', [
        HomeEntry(
          title: 'Send my work',
          description: 'Upload the work saved on this device',
          icon: Icons.cloud_upload_outlined,
          checklistRow: 55,
          doc: 'sync.md#send-my-work-upload',
          builder: _row55,
        ),
        HomeEntry(
          title: 'Download the latest data',
          description: 'Get everything you may see from the server',
          icon: Icons.cloud_download_outlined,
          checklistRow: 54,
          doc: 'sync.md#get-the-latest-from-the-server-pull',
          builder: _row54,
        ),
      ]),
    ],
  ),
];

// The screens both builds open (const entries need top-level functions).
Widget _row50(BuildContext _) => const DashboardScreen();
Widget _row52(BuildContext _) => const RemindersScreen();
Widget _row51(BuildContext _) => const CalendarScreen();
Widget _row53(BuildContext _) => const TrendsScreen();
Widget _row16(BuildContext _) => const LearnersScreen();
Widget _row15(BuildContext _) => const SectionsScreen();
Widget _row14(BuildContext _) => const SchoolsScreen();
Widget _row21(BuildContext _) => const CrlaSectionScreen();
Widget _row25(BuildContext _) => const CrlaExportScreen();
Widget _row24(BuildContext _) => const CrlaThresholdsScreen();
Widget _row27(BuildContext _) => const GstScreen();
Widget _row28(BuildContext _) => const PhilIriSectionScreen();
Widget _row30(BuildContext _) => const LearnerResultsPickScreen();
Widget _row32(BuildContext _) => const PhilIriContentScreen();
Widget _row33(BuildContext _) => const PhilIriThresholdsScreen();
Widget _row36(BuildContext _) => const AralClassesScreen();
Widget _row37(BuildContext _) => const AralSessionsScreen();
Widget _row39(BuildContext _) => const AralLearnerPickScreen(title: 'Check-ins', tab: LearnerAralTab.checkins);
Widget _row38(BuildContext _) => const AralLearnerPickScreen(title: 'IRIP', tab: LearnerAralTab.irip);
Widget _row34(BuildContext _) => const AralRosterScreen();
Widget _row35(BuildContext _) => const AralTutorsScreen();
Widget _row41(BuildContext _) => const AralMaterialsScreen();
Widget _row42(BuildContext _) => const AralLearnerPickScreen(title: 'Readability log', tab: LearnerAralTab.readability);
Widget _row47(BuildContext _) => const SrpScreen();
Widget _row40(BuildContext _) => const AralSettingsScreen();
Widget _row55(BuildContext _) => const UploadScreen();
Widget _row54(BuildContext _) => const PullScreen();
