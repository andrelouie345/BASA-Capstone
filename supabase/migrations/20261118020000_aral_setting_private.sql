-- ARAL memo settings: the setting reader moves out of the API (final review
-- of plan docs/superpowers/plans/2026-11-18-aral-memo-a-settings.md, m2).
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261118010000.
-- App update required on all devices: no (no rule changes; the app never
-- called the function).
--
-- 20261118010000 made public.aral_setting(school, key) SECURITY DEFINER and
-- callable by every signed-in user, so anyone could read any school's ARAL
-- settings through the API, while aral_settings itself shows a user only
-- their own school's row (and the default row). Only the server's checks
-- need it, so it moves to basa_private (no API access), with the same body:
--   1. basa_private.aral_setting(school, key): the school's row, else the
--      default row (school_id null), else null.
--   2. basa_private.aral_setting_int and basa_private.aral_check_session_rules
--      call it (the class cap, session and IRIP triggers call those two, so
--      they need no change).
--   3. public.aral_setting is dropped.
-- RLS: unchanged (aral_settings keeps its policies; no table is touched).

-- 1. The value that counts for a school.
create or replace function basa_private.aral_setting(p_school_id bigint, p_key text)
 returns jsonb language sql stable security definer set search_path to 'public'
as $$
  select coalesce(
    (select settings -> p_key from public.aral_settings
      where school_id = p_school_id and settings ? p_key),
    (select settings -> p_key from public.aral_settings
      where school_id is null and settings ? p_key));
$$;

revoke all on function basa_private.aral_setting(bigint, text) from public, anon, authenticated;

-- 2. Its two callers.
create or replace function basa_private.aral_setting_int(p_school_id bigint, p_key text, p_default integer)
 returns integer language sql stable security definer set search_path to 'public'
as $$
  select coalesce((basa_private.aral_setting(p_school_id, p_key) #>> '{}')::numeric::integer, p_default);
$$;

revoke all on function basa_private.aral_setting_int(bigint, text, integer) from public, anon, authenticated;

create or replace function basa_private.aral_check_session_rules(p_school_id bigint, p_held_on date,
                                                                 p_minutes integer, p_setup text)
 returns void language plpgsql stable security definer set search_path to 'public'
as $$
declare
  v_max integer;
begin
  if coalesce((basa_private.aral_setting(p_school_id, 'sessions_weekdays_only') #>> '{}')::boolean, false)
     and (extract(isodow from p_held_on) in (6, 7) or p_setup = 'weekend') then
    raise exception 'ARAL sessions are held Monday to Friday at this school';
  end if;
  v_max := basa_private.aral_setting_int(p_school_id, 'session_max_minutes', null);
  if v_max is not null and p_minutes > v_max then
    raise exception 'an ARAL session at this school lasts at most % minutes', v_max;
  end if;
end;
$$;

revoke all on function basa_private.aral_check_session_rules(bigint, date, integer, text)
  from public, anon, authenticated;

-- 3. No API reader any more.
drop function if exists public.aral_setting(bigint, text);

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261118020000', 'aral_setting_private', false)
on conflict (id) do nothing;
