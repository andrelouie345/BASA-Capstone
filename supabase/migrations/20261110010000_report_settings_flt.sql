-- report_settings: the FLT toggle (no_comprehension_counts_FLT).
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261109020000.
-- App update required on all devices: no (a new optional key, off by
-- default: an older app reads it as off, which is today's rule).
--
-- Owner decision 2026-11-10 (spec docs/superpowers/specs/2026-11-09-phil-iri-rules-update-design.md,
-- questions list): a Phil-IRI reading from a collection without comprehension
-- questions (e.g. the Foundational Literacy Test) counts as assessed with words
-- read and time alone when the school's setting is on (school row, then the
-- region row, then off). The rule lives in the app (phil_iri_results.dart,
-- PhilIriViewModel); the database only checks the value's type, like
-- sync_auto_approve.
--
-- No table, view or policy is created or changed (no grants needed; RLS as
-- before).

-- Stops (changes nothing) when a stored value already breaks the rule.
do $$
declare
  bad text;
begin
  select string_agg(format('id %s (school %s): %s', id, coalesce(school_id::text, 'region'),
                           settings -> 'no_comprehension_counts_FLT'), '; ' order by id)
    into bad
    from public.report_settings
   where settings ? 'no_comprehension_counts_FLT'
     and jsonb_typeof(settings -> 'no_comprehension_counts_FLT') <> 'boolean';
  if bad is not null then
    raise exception 'report_settings has invalid no_comprehension_counts_FLT values: %. Fix them, then run this migration again.', bad;
  end if;
end $$;

alter table public.report_settings drop constraint if exists report_settings_no_comprehension_counts_flt;
alter table public.report_settings add constraint report_settings_no_comprehension_counts_flt check (
  not (settings ? 'no_comprehension_counts_FLT')
  or jsonb_typeof(settings -> 'no_comprehension_counts_FLT') = 'boolean');

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261110010000', 'report_settings_flt', false)
on conflict (id) do nothing;
