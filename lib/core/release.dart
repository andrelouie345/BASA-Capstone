// lib/core/release.dart

/// Database migrations this build of BASA was made for, oldest first:
/// filename timestamp → name (`supabase/migrations/<id>_<name>.sql`).
///
/// At sign-in the app compares this list with the server's basa_migrations
/// ledger (lib/core/services/version_check.dart). Every new migration file adds
/// its line here in the same commit, and ends by inserting its own ledger row.
const Map<String, String> basaMigrations = {
  '20261018040000': 'baseline',
  '20261018050000': 'aral_readability_logs',
  '20261019010000': 'srp_classes',
  '20261019020000': 'srp_tutor_reads_learners',
  '20261019030000': 'assessment_calendar',
  '20261019040000': 'report_settings',
  '20261019050000': 'calendar_round_pairing',
  '20261019060000': 'aral_idle_session_days',
  '20261020010000': 'basa_migrations',
  '20261020020000': 'sync_uploads',
  '20261021010000': 'sync_followup_updates',
  '20261023010000': 'aral_restore_a1c',
  '20261023020000': 'crla_words_read_from_story',
  '20261023030000': 'aral_ks1_memo_rules',
};
