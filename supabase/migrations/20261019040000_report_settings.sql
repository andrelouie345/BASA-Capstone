-- Report settings (dashboard piece D2). Idempotent: safe to run in the Supabase
-- SQL Editor more than once. Newer than the 20261018040000 baseline: a new
-- deployment runs it after it.
--
-- Settings of the reports (progress monitoring, coordinator reminders): one
-- region-wide row (school_id null, set by the superadmin) and per school an
-- override row (its admin/coordinator). settings is a partial jsonb object;
-- the app applies built-in defaults, then the region row, then the school
-- row, key by key (as aral_settings). Written online and mirrored to the
-- device. Separate from aral_settings: the threshold is not an ARAL rule.
--
-- Keys:
--  * done_threshold: share of a section's learners that must be assessed in a
--    round for it to count as done, a number 0.01-1 (app default 0.85).
--  * updated_by/updated_at stamped by aral_settings_stamp() (same columns).
--
-- RLS (raised with the table, copy of aral_settings):
--  * select: superadmin; everyone signed in reads the region row and their own
--    school's row (tutors included).
--  * insert/update/delete: superadmin; admin/coordinator for their own school's
--    row only. Tutors never write.
--  * anon: nothing.

create table if not exists public.report_settings (
  id          bigint generated always as identity primary key,
  school_id   bigint references public.schools(id) on delete cascade,
  settings    jsonb not null,
  updated_by  uuid references public.users(id),
  updated_at  timestamptz not null default now(),
  constraint report_settings_settings_check check (jsonb_typeof(settings) = 'object'),
  constraint report_settings_done_threshold check (
    not (settings ? 'done_threshold')
    or (jsonb_typeof(settings -> 'done_threshold') = 'number'
        and (settings ->> 'done_threshold')::numeric between 0.01 and 1))
);
create unique index if not exists report_settings_school_key
  on public.report_settings (coalesce(school_id, 0));

drop trigger if exists report_settings_stamp on public.report_settings;
create trigger report_settings_stamp
  before insert or update on public.report_settings
  for each row execute function public.aral_settings_stamp();

alter table public.report_settings enable row level security;
revoke all on public.report_settings from anon;

drop policy if exists report_settings_select on public.report_settings;
create policy report_settings_select on public.report_settings
  for select to authenticated
  using (is_superadmin() or school_id is null or school_id = current_user_school_id());

drop policy if exists report_settings_write on public.report_settings;
create policy report_settings_write on public.report_settings
  to authenticated
  using (is_superadmin() or (current_user_role() in ('admin', 'coordinator')
         and school_id is not null and school_id = current_user_school_id()))
  with check (is_superadmin() or (current_user_role() in ('admin', 'coordinator')
              and school_id is not null and school_id = current_user_school_id()));
