# BASA — Users & Login Module: Setup Guide

This covers standing up the backend for a **new school deployment** and
bootstrapping its first admin. It assumes a fresh Supabase project — cloud
or self-hosted LAN — with nothing configured yet.

> Note: this schema is currently only documented here, not tracked as a
> real Supabase migration file. Turning it into one is a known follow-up,
> not yet done.

## 1. Provision the backend

Create a new Supabase cloud project (supabase.com) or stand up a
self-hosted LAN instance. Note its **URL** and **anon key** — that's all
this specific install needs to know about Supabase.

## 2. Apply the schema

Run the following against the new project's SQL editor, in order.

```sql
-- Core data
CREATE TABLE public.schools (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  school_id text NOT NULL UNIQUE,
  school_name text NOT NULL,
  region text,
  division text,
  CONSTRAINT schools_pkey PRIMARY KEY (id)
);

CREATE TABLE public.sections (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  school_id bigint NOT NULL,
  school_year text NOT NULL,
  grade_level text NOT NULL,
  section_name text NOT NULL,
  CONSTRAINT sections_pkey PRIMARY KEY (id),
  CONSTRAINT sections_school_id_fkey FOREIGN KEY (school_id) REFERENCES public.schools(id)
);

CREATE TABLE public.students (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  lrn text NOT NULL UNIQUE,
  last_name text NOT NULL,
  first_name text NOT NULL,
  middle_name text,
  sex text,
  birth_date date,
  mother_tongue text,
  ip_group text,
  religion text,
  address_street text,
  barangay text,
  municipality text,
  province text,
  father_name text,
  mother_maiden_name text,
  guardian_name text,
  guardian_relationship text,
  contact_number text,
  learning_modality text,
  remarks text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT students_pkey PRIMARY KEY (id)
);

CREATE TABLE public.enrollments (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  student_id bigint NOT NULL,
  section_id bigint NOT NULL,
  school_year text NOT NULL,
  status text NOT NULL DEFAULT 'active'::text,
  CONSTRAINT enrollments_pkey PRIMARY KEY (id),
  CONSTRAINT enrollments_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(id),
  CONSTRAINT enrollments_section_id_fkey FOREIGN KEY (section_id) REFERENCES public.sections(id)
);

CREATE TABLE public.import_conflicts (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  lrn text NOT NULL,
  section_id bigint,
  reason text NOT NULL,
  incoming_data jsonb NOT NULL,
  existing_student_id bigint,
  status text NOT NULL DEFAULT 'pending'::text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT import_conflicts_pkey PRIMARY KEY (id),
  CONSTRAINT import_conflicts_section_id_fkey FOREIGN KEY (section_id) REFERENCES public.sections(id),
  CONSTRAINT import_conflicts_existing_student_id_fkey FOREIGN KEY (existing_student_id) REFERENCES public.students(id)
);

-- Users & auth
CREATE TABLE public.users (
  id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  email text NOT NULL UNIQUE,
  full_name text NOT NULL,
  role text NOT NULL CHECK (role IN ('admin', 'coordinator', 'tutor')),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  created_by uuid REFERENCES public.users(id),
  CONSTRAINT users_pkey PRIMARY KEY (id)
);

CREATE TABLE public.login_logs (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  user_id uuid REFERENCES public.users(id),
  email_attempted text NOT NULL,
  success boolean NOT NULL,
  method text NOT NULL,
  timestamp timestamp with time zone NOT NULL DEFAULT now(),
  failure_reason text,
  CONSTRAINT login_logs_pkey PRIMARY KEY (id)
);

-- Helper: avoids infinite RLS recursion when a policy needs to check
-- the caller's own role (SECURITY DEFINER bypasses RLS inside itself)
CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT role FROM public.users WHERE id = auth.uid();
$$;

-- RLS
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.login_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own profile"
ON public.users FOR SELECT
TO authenticated
USING (auth.uid() = id);

CREATE POLICY "Admins and coordinators can read all users"
ON public.users FOR SELECT
TO authenticated
USING (public.current_user_role() IN ('admin', 'coordinator'));

CREATE POLICY "Admins and coordinators can update users"
ON public.users FOR UPDATE
TO authenticated
USING (public.current_user_role() IN ('admin', 'coordinator'))
WITH CHECK (public.current_user_role() IN ('admin', 'coordinator'));

CREATE POLICY "Anyone can insert a login attempt"
ON public.login_logs FOR INSERT
TO anon, authenticated
WITH CHECK (true);

CREATE POLICY "Admins and coordinators can read login logs"
ON public.login_logs FOR SELECT
TO authenticated
USING (public.current_user_role() IN ('admin', 'coordinator'));
```

No `INSERT`/`DELETE` policies exist for `users` on purpose — account
creation only ever happens through the Edge Function below, which uses
the service role key and bypasses RLS entirely.

## 3. Deploy the Edge Functions

```
supabase login
supabase init
supabase link --project-ref <your-project-ref>
supabase functions deploy create-user
supabase functions deploy bootstrap-admin
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are
auto-injected into deployed functions — nothing to configure manually.

## 4. Point the app at this project

From the console (`dart run lib/console/main.dart`):

```
config-set-cloud-url <your-project-url>
config-set-cloud-anon-key <your-anon-key>
```

> Command names above are inferred from usage patterns elsewhere in the
> console, not confirmed against `config_commands.dart` directly —
> verify against the real command names via the `help` command if these
> don't match.

## 5. Bootstrap the first admin

```
bootstrap-admin cloud <admin-email> <admin full name>
```

This only works once per project — it's self-limiting and refuses once
any user already exists. The new admin's temporary password is
**`password`**, and they'll be required to change it on first login.

## 6. Day-to-day admin commands

```
sign-in cloud <email> <password>
whoami
change-password <new password>
user-create <email> <admin|coordinator|tutor> <full name>
user-list
user-set-active <userId> <true|false>
sign-out
```

## Known gaps (not yet built)

- **Schema isn't a tracked migration** — this file's SQL block is the
  closest thing to one right now; copy-pasted per new project.
- **Login is always online** — no offline/cached fallback exists.
- **Cloud login-log sync has no retry** — an attempt logged locally while
  offline never gets flushed to the cloud once connectivity returns.
- **Local cache isn't scoped per user yet** — a second user signing in on
  a shared device is intended to replace the local cache (with a warning
  to the user), but this isn't implemented.
- **No separate admin/tutor builds** — role gating is currently
  client-side/UI-level only, not enforced by excluding code from the
  build.
- **LAN/self-hosted profile is untested end-to-end.**
- **`tutor_section_assignments` doesn't exist yet** — there's no way yet
  to scope which sections/students a given tutor can see.
