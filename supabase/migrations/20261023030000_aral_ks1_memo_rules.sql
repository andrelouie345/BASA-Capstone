-- ARAL Key Stage 1 (Grades 1-3) follows DepEd Memorandum 064 s. 2025
-- (owner decision 2026-10-23, guideline review of command pass batch A4).
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261023020000.
-- App update required on all devices: yes (a rule change: an older app
-- proposes KS1 Developing/Transitioning learners and keeps them in ARAL, and
-- can't read the new exit reason, so the device and the server would
-- disagree until the app is updated).
--
-- Rules (the app applies them: lib/core/services/aral_rules.dart,
-- AralViewModel):
--   * KS1 takes Low and High Emerging learners; Developing and Transitioning
--     stay in the regular class (Encl. 2 item 4). A school with the needed
--     personnel may extend the program to them (Encl. 1 item 7): the new
--     aral_settings key ks1_extended (true/false, absent = false).
--   * A KS1 learner whose latest CRLA is Developing or Transitioning leaves
--     ARAL for classroom-based remediation (Encl. 2 item 23, Figures 1-2)
--     unless the school runs the extended program. The exit reason is the new
--     'classroom_support' (the memo's "exit with classroom support", Encl. 3
--     item 37.2; also usable by hand for KS2-3).
--   * The CRLA that counts: Grade 1 Mother Tongue (else Filipino), Grade 2
--     Filipino, Grade 3 English (Encl. 2 Table 2). App only.
--
-- Changes only two CHECK constraints. Stops (changes nothing) when a stored
-- ks1_extended value is not true/false. RLS: unchanged (constraints only;
-- aral_enrollments and aral_settings keep their policies).

do $$
declare
  bad text;
begin
  select string_agg(format('id %s (school %s): %s', id, coalesce(school_id::text, 'region'),
                           settings -> 'ks1_extended'), '; ' order by id)
    into bad
    from public.aral_settings
   where settings ? 'ks1_extended' and jsonb_typeof(settings -> 'ks1_extended') <> 'boolean';
  if bad is not null then
    raise exception 'aral_settings has ks1_extended values that are not true/false: %. '
                    'Fix them, then run this migration again.', bad;
  end if;
end $$;

alter table public.aral_enrollments drop constraint if exists aral_enrollments_exit_reason_check;
alter table public.aral_enrollments add constraint aral_enrollments_exit_reason_check check (
  exit_reason = any (array['grade_level_ready', 'transferred_out', 'dropped_out', 'other', 'classroom_support']));

alter table public.aral_settings drop constraint if exists aral_settings_ks1_extended;
alter table public.aral_settings add constraint aral_settings_ks1_extended check (
  not (settings ? 'ks1_extended') or jsonb_typeof(settings -> 'ks1_extended') = 'boolean');

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261023030000', 'aral_ks1_memo_rules', true)
on conflict (id) do nothing;
