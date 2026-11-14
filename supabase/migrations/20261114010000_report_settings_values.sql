-- report_settings: the six Phil-IRI value switches (values_aral,
-- values_bosy_masterlist, values_form2b, values_srp, values_learner_pages,
-- values_ranking).
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261113020000.
-- App update required on all devices: no (new optional keys: an older app
-- ignores them and shows carried values, today's rule; only the new ranking
-- list reads values_ranking).
--
-- Owner + ma decisions 2026-11-14 (spec
-- docs/superpowers/specs/2026-11-14-phil-iri-value-sources-design.md, D1-D3):
-- each list shows ONE kind of Phil-IRI value, chosen per school (school row,
-- then the region row, then the default): "carried" (the best so far, carried
-- into later rounds) or "actual" (each round's own reading). Defaults: ranking
-- actual, the rest carried. The rule lives in the app (report_setting.dart,
-- the list ViewModels); the database only checks that a stored value is one
-- of the two strings, like no_comprehension_counts_FLT.
--
-- No table, view or policy is created or changed (no grants needed; RLS as
-- before).

-- Stops (changes nothing) when a stored value already breaks the rule.
do $$
declare
  bad text;
begin
  select string_agg(format('id %s (school %s): %s = %s', s.id, coalesce(s.school_id::text, 'region'),
                           k.key, s.settings -> k.key), '; ' order by s.id, k.key)
    into bad
    from public.report_settings s
    cross join (values ('values_aral'), ('values_bosy_masterlist'), ('values_form2b'), ('values_srp'),
                       ('values_learner_pages'), ('values_ranking')) as k(key)
   where s.settings ? k.key
     and not (jsonb_typeof(s.settings -> k.key) = 'string'
              and s.settings ->> k.key in ('carried', 'actual'));
  if bad is not null then
    raise exception 'report_settings has invalid Phil-IRI value switches: %. Each must be "carried" or "actual". Fix them, then run this migration again.', bad;
  end if;
end $$;

alter table public.report_settings drop constraint if exists report_settings_values_aral;
alter table public.report_settings add constraint report_settings_values_aral check (
  not (settings ? 'values_aral')
  or (jsonb_typeof(settings -> 'values_aral') = 'string' and settings ->> 'values_aral' in ('carried', 'actual')));

alter table public.report_settings drop constraint if exists report_settings_values_bosy_masterlist;
alter table public.report_settings add constraint report_settings_values_bosy_masterlist check (
  not (settings ? 'values_bosy_masterlist')
  or (jsonb_typeof(settings -> 'values_bosy_masterlist') = 'string'
      and settings ->> 'values_bosy_masterlist' in ('carried', 'actual')));

alter table public.report_settings drop constraint if exists report_settings_values_form2b;
alter table public.report_settings add constraint report_settings_values_form2b check (
  not (settings ? 'values_form2b')
  or (jsonb_typeof(settings -> 'values_form2b') = 'string' and settings ->> 'values_form2b' in ('carried', 'actual')));

alter table public.report_settings drop constraint if exists report_settings_values_srp;
alter table public.report_settings add constraint report_settings_values_srp check (
  not (settings ? 'values_srp')
  or (jsonb_typeof(settings -> 'values_srp') = 'string' and settings ->> 'values_srp' in ('carried', 'actual')));

alter table public.report_settings drop constraint if exists report_settings_values_learner_pages;
alter table public.report_settings add constraint report_settings_values_learner_pages check (
  not (settings ? 'values_learner_pages')
  or (jsonb_typeof(settings -> 'values_learner_pages') = 'string'
      and settings ->> 'values_learner_pages' in ('carried', 'actual')));

alter table public.report_settings drop constraint if exists report_settings_values_ranking;
alter table public.report_settings add constraint report_settings_values_ranking check (
  not (settings ? 'values_ranking')
  or (jsonb_typeof(settings -> 'values_ranking') = 'string'
      and settings ->> 'values_ranking' in ('carried', 'actual')));

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261114010000', 'report_settings_values', false)
on conflict (id) do nothing;
