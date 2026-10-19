-- ARAL settings: idle_session_days (dashboard D3, tutor reminders).
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261019050000.
-- App update required on all devices: no (a new optional key; older apps
-- never write it and ignore it on read).
--
-- A tutor with active ARAL learners gets a "no session lately" reminder when
-- their last session is more than idle_session_days before today. The key
-- lives in aral_settings.settings like checkin_pass_pct (region row, school
-- override). Absent = the app default, 7 days. Allowed: a whole number of
-- days, 1-60.
--
-- Stops (changes nothing) when a stored value already breaks the rule,
-- listing the rows, so nothing is changed silently. RLS: unchanged (a
-- constraint only; aral_settings keeps its policies).

do $$
declare
  bad text;
begin
  select string_agg(format('id %s (school %s): %s', id, coalesce(school_id::text, 'region'),
                           settings -> 'idle_session_days'), '; ' order by id)
    into bad
    from public.aral_settings
   where settings ? 'idle_session_days'
     and not (jsonb_typeof(settings -> 'idle_session_days') = 'number'
              and (settings ->> 'idle_session_days')::numeric between 1 and 60
              and (settings ->> 'idle_session_days')::numeric = trunc((settings ->> 'idle_session_days')::numeric));
  if bad is not null then
    raise exception 'aral_settings has idle_session_days values outside 1-60 whole days: %. '
                    'Fix them, then run this migration again.', bad;
  end if;
end $$;

alter table public.aral_settings drop constraint if exists aral_settings_idle_session_days;
alter table public.aral_settings add constraint aral_settings_idle_session_days check (
  not (settings ? 'idle_session_days')
  or (jsonb_typeof(settings -> 'idle_session_days') = 'number'
      and (settings ->> 'idle_session_days')::numeric between 1 and 60
      and (settings ->> 'idle_session_days')::numeric = trunc((settings ->> 'idle_session_days')::numeric)));
