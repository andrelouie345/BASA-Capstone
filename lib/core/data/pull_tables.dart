// lib/core/data/pull_tables.dart
//
// The tables a pull downloads and rewrites (spec
// docs/superpowers/specs/2026-10-20-sync-design.md, section 7). Shared by the
// download source (data/remote/sync_download_supabase.dart) and the local
// merge (data/local/sync_local_repository_sqlite.dart).
library;

/// Parents before children (foreign keys), mapped to the column used for
/// stable paging. Part tables must come after crla_assessments: the local
/// variant-check triggers look up the parent row. Likewise the Phil-IRI
/// child tables come after phil_iri_assessments, whose origin tells the local
/// triggers to leave mirrored rows alone.
const pullOrder = <String, String>{
  'schools': 'id',
  'users': 'id',
  'assessment_calendar': 'id',
  'report_settings': 'id',
  'sections': 'id',
  'tutor_section_assignments': 'id',
  'students': 'id',
  'enrollments': 'id',
  'crla_stories': 'id',
  'crla_thresholds': 'id',
  'crla_assessments': 'id',
  'crla_part1_standard': 'assessment_id',
  'crla_part1_english': 'assessment_id',
  'crla_part2_fluency': 'assessment_id',
  'phil_iri_collections': 'id',
  'phil_iri_rubric_criteria': 'id',
  'phil_iri_passages': 'id',
  'phil_iri_questions': 'id',
  'phil_iri_thresholds': 'id',
  'phil_iri_gst_results': 'id',
  'phil_iri_assessments': 'id',
  'phil_iri_readings': 'id',
  'phil_iri_miscues': 'id',
  'phil_iri_answers': 'id',
  'phil_iri_rubric_scores': 'id',
  'aral_enrollments': 'id',
  'aral_sessions': 'id',
  'aral_attendance': 'id',
  'aral_tutor_settings': 'tutor_id',
  'aral_irip_targets': 'id',
  'aral_irip_weeks': 'id',
  'aral_settings': 'id',
  'aral_checkin_tools': 'id',
  'aral_checkin_items': 'id',
  'aral_checkins': 'id',
  'aral_checkin_answers': 'id',
  'aral_materials': 'id',
  'aral_material_links': 'id',
  'aral_readability_logs': 'id',
  'srp_classes': 'id',
  'srp_class_members': 'id',
};

/// Local tables a pull empties before writing (children first). Everything
/// the signed-in user can read comes back from the cloud; regions (seed data)
/// and login_logs (this device's sign-in history) are kept. import_conflicts
/// lives in the cloud only; its local copy is unused but may hold old rows.
const pullClearOrder = [
  'srp_class_members',
  'srp_classes',
  'aral_readability_logs',
  'aral_material_links',
  'aral_materials',
  'aral_checkin_answers',
  'aral_checkins',
  'aral_checkin_items',
  'aral_checkin_tools',
  'aral_settings',
  'aral_irip_weeks',
  'aral_irip_targets',
  'aral_tutor_settings',
  'aral_attendance',
  'aral_sessions',
  'aral_enrollments',
  'phil_iri_rubric_scores',
  'phil_iri_answers',
  'phil_iri_miscues',
  'phil_iri_readings',
  'phil_iri_assessments',
  'phil_iri_gst_results',
  'phil_iri_thresholds',
  'phil_iri_questions',
  'phil_iri_passages',
  'phil_iri_rubric_criteria',
  'phil_iri_collections',
  'crla_part2_fluency',
  'crla_part1_english',
  'crla_part1_standard',
  'crla_assessments',
  'crla_thresholds',
  'crla_stories',
  'import_conflicts',
  'report_settings',
  'assessment_calendar',
  'enrollments',
  'students',
  'tutor_section_assignments',
  'sections',
  'users',
  'schools',
];

/// The 18 synced tables (parents before children, as pull-cloud's order) and
/// the column that keys a record.
const syncedTables = <String, String>{
  'crla_assessments': 'id',
  'crla_part1_standard': 'assessment_id',
  'crla_part1_english': 'assessment_id',
  'crla_part2_fluency': 'assessment_id',
  'phil_iri_gst_results': 'id',
  'phil_iri_assessments': 'id',
  'phil_iri_readings': 'id',
  'phil_iri_miscues': 'id',
  'phil_iri_answers': 'id',
  'phil_iri_rubric_scores': 'id',
  'aral_enrollments': 'id',
  'aral_sessions': 'id',
  'aral_attendance': 'id',
  'aral_tutor_settings': 'tutor_id',
  'aral_irip_weeks': 'id',
  'aral_checkins': 'id',
  'aral_checkin_answers': 'id',
  'aral_readability_logs': 'id',
};

/// Child tables that travel with their owner record: (parent table, column
/// holding the parent's key).
const syncedParents = <String, (String, String)>{
  'crla_part1_standard': ('crla_assessments', 'assessment_id'),
  'crla_part1_english': ('crla_assessments', 'assessment_id'),
  'crla_part2_fluency': ('crla_assessments', 'assessment_id'),
  'phil_iri_readings': ('phil_iri_assessments', 'assessment_id'),
  'phil_iri_rubric_scores': ('phil_iri_assessments', 'assessment_id'),
  'phil_iri_miscues': ('phil_iri_readings', 'reading_id'),
  'phil_iri_answers': ('phil_iri_readings', 'reading_id'),
  'aral_attendance': ('aral_sessions', 'session_id'),
  'aral_checkin_answers': ('aral_checkins', 'checkin_id'),
};
