-- M1: auth / users / login_logs hardening.
-- Idempotent: safe to run in the Supabase SQL Editor more than once.
--
-- Fixes, each verified against the dev project on 2026-10-12:
--  1. A deactivated user kept full data access (and could reactivate itself),
--     because none of the RLS helper functions looked at users.is_active.
--  2. users_update_scoped allowed a school admin/coordinator to rewrite ANY
--     column of a same-school user (role, email, school_id, created_by).
--  3. login_logs accepted inserts with any user_id / success value from anon,
--     so the audit trail could be forged.

begin;

-- 1. Helpers treat an inactive account as having no role, school or assignments.
--    Every scoped policy goes through these, so this closes access everywhere.

create or replace function public.current_user_role()
 returns text language sql stable security definer set search_path to 'public'
as $$
  select role from public.users where id = auth.uid() and is_active;
$$;

create or replace function public.current_user_school_id()
 returns bigint language sql stable security definer set search_path to 'public'
as $$
  select school_id from public.users where id = auth.uid() and is_active;
$$;

create or replace function public.is_superadmin()
 returns boolean language sql stable security definer set search_path to 'public'
as $$
  select coalesce(
    (select role = 'admin' and school_id is null
       from public.users where id = auth.uid() and is_active),
    false);
$$;

create or replace function public.tutor_has_section(p_section_id bigint)
 returns boolean language sql stable security definer set search_path to 'public'
as $$
  select public.current_user_role() = 'tutor' and exists (
    select 1 from public.tutor_section_assignments
    where tutor_id = auth.uid() and section_id = p_section_id
  );
$$;

create or replace function public.tutor_has_student(p_student_id bigint)
 returns boolean language sql stable security definer set search_path to 'public'
as $$
  select public.current_user_role() = 'tutor' and exists (
    select 1
    from public.enrollments e
    join public.tutor_section_assignments tsa on tsa.section_id = e.section_id
    where e.student_id = p_student_id and tsa.tutor_id = auth.uid()
  );
$$;

-- tsa_select_scoped checked tutor_id = auth.uid() directly; route it through
-- the active-aware role helper like everything else.
drop policy if exists tsa_select_scoped on public.tutor_section_assignments;
create policy tsa_select_scoped on public.tutor_section_assignments
  for select to authenticated
  using (
    is_superadmin()
    or (current_user_role() = 'tutor' and tutor_id = auth.uid())
    or (current_user_role() in ('admin', 'coordinator')
        and section_in_school(section_id, current_user_school_id()))
  );

-- 2. users: clients may only flip is_active, never on their own row.
--    role / school_id / email changes need a server-side path (Edge Function).
--    "Users can read own profile" is kept on purpose: sign-in needs it to
--    report "account is inactive".

revoke update on public.users from anon, authenticated;
grant update (is_active) on public.users to authenticated;

drop policy if exists users_update_scoped on public.users;
create policy users_update_scoped on public.users
  for update to authenticated
  using (
    id <> auth.uid()
    and (is_superadmin()
         or (current_user_role() in ('admin', 'coordinator')
             and school_id = current_user_school_id()))
  )
  with check (
    id <> auth.uid()
    and (is_superadmin()
         or (current_user_role() in ('admin', 'coordinator')
             and school_id = current_user_school_id()))
  );

-- 3. login_logs: a row may only claim the caller's own identity.
--    Pre-auth failures (wrong password, anon client) must be anonymous failures.
--    The client timestamp is still trusted (offline logs will sync later);
--    revisit when sync is designed.

drop policy if exists "Anyone can insert a login attempt" on public.login_logs;
drop policy if exists login_logs_insert_own on public.login_logs;
create policy login_logs_insert_own on public.login_logs
  for insert to anon, authenticated
  with check (
    (user_id is null and success = false)
    or user_id = auth.uid()
  );

commit;
