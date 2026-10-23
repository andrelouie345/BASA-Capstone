-- ARAL roster: restore piece A1c (archived 20261015070000), which never
-- reached the cloud project the baseline was squashed from.
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261021010000.
-- App update required on all devices: no (the app already applies these rules
-- on the device; the server now accepts what it sends and enforces the cap too).
--
-- Found 2026-10-23 (tutor build T6 kit): the server lacked
--   * aral_check_section_cap: aral_enrollments_before_update (from A4,
--     20261016020000) calls it, so every server-side reactivation, section
--     move or school-year change of an ARAL learner failed with "function
--     aral_check_section_cap(bigint, bigint, text) does not exist" (a
--     coordinator's sync upload of aral-reactivate, for one);
--   * the cap check on insert: the server no longer refused a 16th active
--     learner in a section (each device still did, but two devices could
--     upload more than 15 together);
--   * 'foundational' in key_stage / suggested_key_stage and the track rule for
--     it: a Foundational (non-reader) enrollment made on a device was refused
--     on upload.
--
-- Rules restored (ma's revised rules, A1c):
--   * key_stage and suggested_key_stage allow 'foundational'; foundational and
--     KS1 have no track, KS2-3 have one.
--   * A section has at most 15 ACTIVE ARAL learners per school year, checked
--     when a row becomes active in a section: insert, reactivation, or a move.
--     Rows already over 15 are not touched. Serialized per section and year
--     with a transaction-scoped advisory lock, so two coordinators can't both
--     take the 15th place.
--
-- RLS: unchanged. The trigger functions stay SECURITY DEFINER with search_path
-- public, so the count sees every row of the section, including ones the
-- caller can't read. Nobody calls the cap check directly: execute is revoked,
-- so it can't be used to probe other schools' sections.

-- Key-stage and track checks (inline checks got generated names; find them by
-- definition, so a second run replaces its own constraints too).
do $$
declare
  c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.aral_enrollments'::regclass and contype = 'c'
      and (pg_get_constraintdef(oid) like '%key_stage%')
  loop
    execute format('alter table public.aral_enrollments drop constraint %I', c.conname);
  end loop;
end;
$$;

alter table public.aral_enrollments
  add constraint aral_enrollments_key_stage_check
    check (key_stage in ('foundational', 'ks1', 'ks2', 'ks3')),
  add constraint aral_enrollments_suggested_key_stage_check
    check (suggested_key_stage in ('foundational', 'ks1', 'ks2', 'ks3')),
  add constraint aral_enrollments_track
    check ((key_stage in ('foundational', 'ks1')) = (track is null));

-- At most 15 active learners per section and year.
create or replace function public.aral_check_section_cap(p_id bigint, p_section_id bigint, p_school_year text)
 returns void language plpgsql security definer set search_path to 'public'
as $$
begin
  perform pg_advisory_xact_lock(hashtext('aral_section_cap:' || p_section_id::text || ':' || p_school_year));
  if (select count(*) from public.aral_enrollments
      where section_id = p_section_id and school_year = p_school_year and status = 'active'
        and id is distinct from p_id) >= 15 then
    raise exception 'an ARAL section has at most 15 active learners';
  end if;
end;
$$;

-- Today's insert trigger (baseline) plus the cap check A1c gave it.
-- aral_enrollments_before_update already calls the cap check (A4).
create or replace function public.aral_enrollments_before_insert()
 returns trigger language plpgsql security definer set search_path to 'public'
as $$
begin
  if auth.uid() is not null then
    new.created_by := auth.uid();
    new.status := 'active';
    new.exited_on := null;
    new.exit_reason := null;
  end if;
  new.created_at := now();
  new.updated_at := now();
  perform aral_check_tutor(new.tutor_id, new.school_id);
  if new.status = 'active' then
    perform aral_check_section_cap(null, new.section_id, new.school_year);
  end if;
  return new;
end;
$$;

revoke all on function public.aral_check_section_cap(bigint, bigint, text) from public, anon, authenticated;

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261023010000', 'aral_restore_a1c', false)
on conflict (id) do nothing;
