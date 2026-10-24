-- ARAL sessions: the read policy checks the row's own columns again, so an
-- upload can insert sessions.
-- Idempotent: safe to run in the Supabase SQL Editor more than once. Newer
-- than 20261024010000.
-- App update required on all devices: no (a policy repair; who reads what
-- does not change).
--
-- Why (command pass r6, finding F14): 20261023040000 made aral_sessions_select
-- call aral_session_readable(id), which looks the session up by its id.
-- sync_apply inserts every row with "insert ... returning id", and a returned
-- row must pass the SELECT policy; the lookup cannot see the row being
-- inserted, so every uploaded session was refused ("new row violates
-- row-level security policy"), from tutors and coordinators alike.
--
-- Rule (unchanged in effect): a session is read by the superadmin, an admin
-- or coordinator of its school, its tutor or its class's tutor (all checked
-- on the row's columns, as aral_session_writable does), or, through
-- aral_session_readable(id), a tutor one of whose current learners has a
-- mark in it (its header only).

drop policy if exists aral_sessions_select on public.aral_sessions;
create policy aral_sessions_select on public.aral_sessions for select to authenticated
  using (is_superadmin()
         or (current_user_role() in ('admin', 'coordinator') and school_id = current_user_school_id())
         or (current_user_role() = 'tutor' and (tutor_id = auth.uid() or aral_tutor_has_class(class_id)))
         or aral_session_readable(id));

-- This migration's own ledger row (always last).
insert into public.basa_migrations (id, name, app_update_required)
values ('20261024020000', 'aral_sessions_select_returning', false)
on conflict (id) do nothing;
