# BASA — Users, Schools & Roster Backend Setup Guide

This covers standing up the backend for a **new deployment** and
bootstrapping its first superadmin. It assumes a fresh Supabase project —
cloud or self-hosted LAN — with nothing configured yet.

This backend is multi-school capable by design: one Supabase project can
host many schools (a shared regional deployment), or you can run one
project per school if a region prefers full isolation — nothing about the
schema or app forces either choice.

> Note: this schema is currently only documented here, not tracked as a
> real Supabase migration file. Turning it into one is a known follow-up,
> not yet done.

## 1. Provision the backend

Create a new Supabase cloud project (supabase.com) or stand up a
self-hosted LAN instance. Note its **URL** and **anon key**.

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
  CONSTRAINT sections_school_id_school_year_grade_level_section_name_key
    UNIQUE (school_id, school_year, grade_level, section_name),
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
  school_id bigint REFERENCES public.schools(id), -- auto-synced, see trigger below
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
  CONSTRAINT enrollments_student_id_school_year_key UNIQUE (student_id, school_year),
  CONSTRAINT enrollments_student_id_fkey FOREIGN KEY (student_id) REFERENCES public.students(id),
  CONSTRAINT enrollments_section_id_fkey FOREIGN KEY (section_id) REFERENCES public.sections(id)
);

CREATE TABLE public.import_conflicts (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  lrn text NOT NULL,
  section_id bigint REFERENCES public.sections(id),
  reason text NOT NULL,
  incoming_data text NOT NULL, -- JSON-encoded string; NOT jsonb (matches ImportConflict.incomingDataJson)
  existing_student_id bigint REFERENCES public.students(id),
  status text NOT NULL DEFAULT 'pending'::text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT import_conflicts_pkey PRIMARY KEY (id)
);

CREATE TABLE public.tutor_section_assignments (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  tutor_id uuid NOT NULL REFERENCES public.users(id),
  section_id bigint NOT NULL REFERENCES public.sections(id),
  assigned_by uuid REFERENCES public.users(id),
  assigned_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT tutor_section_assignments_pkey PRIMARY KEY (id),
  CONSTRAINT tutor_section_assignments_tutor_section_key UNIQUE (tutor_id, section_id)
);

-- Users & auth
CREATE TABLE public.users (
  id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  email text NOT NULL UNIQUE,
  full_name text NOT NULL,
  role text NOT NULL CHECK (role IN ('admin', 'coordinator', 'tutor')),
  school_id bigint REFERENCES public.schools(id), -- NULL + role='admin' = superadmin
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

-- Helpers (all SECURITY DEFINER — needed to avoid RLS recursion when a
-- policy has to check the caller's own row, or a related table's row,
-- from inside another table's policy)
CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS text LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$
  SELECT role FROM public.users WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.current_user_school_id()
RETURNS bigint LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT school_id FROM public.users WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.is_superadmin()
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT role = 'admin' AND school_id IS NULL FROM public.users WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.section_in_school(p_section_id bigint, p_school_id bigint)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM public.sections WHERE id = p_section_id AND school_id = p_school_id);
$$;

CREATE OR REPLACE FUNCTION public.tutor_has_section(p_section_id bigint)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.tutor_section_assignments
    WHERE tutor_id = auth.uid() AND section_id = p_section_id
  );
$$;

CREATE OR REPLACE FUNCTION public.tutor_has_student(p_student_id bigint)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.enrollments e
    JOIN public.tutor_section_assignments tsa ON tsa.section_id = e.section_id
    WHERE e.student_id = p_student_id AND tsa.tutor_id = auth.uid()
  );
$$;

-- Trigger: keeps students.school_id pointed at the newest enrollment's school
CREATE OR REPLACE FUNCTION public.sync_student_school_id()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.students
  SET school_id = (SELECT school_id FROM public.sections WHERE id = NEW.section_id)
  WHERE id = NEW.student_id;
  RETURN NEW;
END;
$$;

CREATE TRIGGER enrollments_sync_student_school
  AFTER INSERT OR UPDATE ON public.enrollments
  FOR EACH ROW EXECUTE FUNCTION public.sync_student_school_id();

-- Trigger: validates a tutor_section_assignments row on write
CREATE OR REPLACE FUNCTION public.validate_tutor_section_assignment()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_tutor_role text;
  v_tutor_school bigint;
  v_section_school bigint;
BEGIN
  SELECT role, school_id INTO v_tutor_role, v_tutor_school
  FROM public.users WHERE id = NEW.tutor_id;

  IF v_tutor_role IS DISTINCT FROM 'tutor' THEN
    RAISE EXCEPTION 'tutor_id % is not a tutor (role: %)', NEW.tutor_id, v_tutor_role;
  END IF;

  SELECT school_id INTO v_section_school FROM public.sections WHERE id = NEW.section_id;

  IF v_tutor_school IS DISTINCT FROM v_section_school THEN
    RAISE EXCEPTION 'tutor % (school %) and section % (school %) belong to different schools',
      NEW.tutor_id, v_tutor_school, NEW.section_id, v_section_school;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER tutor_section_assignments_validate
  BEFORE INSERT OR UPDATE ON public.tutor_section_assignments
  FOR EACH ROW EXECUTE FUNCTION public.validate_tutor_section_assignment();

-- RLS
ALTER TABLE public.schools ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.import_conflicts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tutor_section_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.login_logs ENABLE ROW LEVEL SECURITY;
-- ^ Don't assume this is on by default for a table you create — it
--   wasn't, for schools/students, and cost real debugging time to catch.

CREATE POLICY "schools_select_scoped" ON public.schools FOR SELECT TO authenticated
  USING (is_superadmin() OR (current_user_role() IN ('admin','coordinator') AND id = current_user_school_id()));
CREATE POLICY "schools_insert_superadmin" ON public.schools FOR INSERT TO authenticated
  WITH CHECK (is_superadmin());
CREATE POLICY "schools_update_scoped" ON public.schools FOR UPDATE TO authenticated
  USING (is_superadmin() OR (current_user_role() IN ('admin','coordinator') AND id = current_user_school_id()))
  WITH CHECK (is_superadmin() OR (current_user_role() IN ('admin','coordinator') AND id = current_user_school_id()));

CREATE POLICY "sections_select_scoped" ON public.sections FOR SELECT TO authenticated
  USING (is_superadmin() OR (current_user_role() IN ('admin','coordinator') AND school_id = current_user_school_id())
         OR (current_user_role() = 'tutor' AND tutor_has_section(id)));
CREATE POLICY "sections_insert_scoped" ON public.sections FOR INSERT TO authenticated
  WITH CHECK (is_superadmin() OR (current_user_role() IN ('admin','coordinator') AND school_id = current_user_school_id()));
CREATE POLICY "sections_update_scoped" ON public.sections FOR UPDATE TO authenticated
  USING (is_superadmin() OR (current_user_role() IN ('admin','coordinator') AND school_id = current_user_school_id()))
  WITH CHECK (is_superadmin() OR (current_user_role() IN ('admin','coordinator') AND school_id = current_user_school_id()));
CREATE POLICY "sections_delete_scoped" ON public.sections FOR DELETE TO authenticated
  USING (is_superadmin() OR (current_user_role() IN ('admin','coordinator') AND school_id = current_user_school_id()));

CREATE POLICY "students_select_scoped" ON public.students FOR SELECT TO authenticated
  USING (is_superadmin() OR (current_user_role() IN ('admin','coordinator') AND school_id = current_user_school_id())
         OR (current_user_role() = 'tutor' AND tutor_has_student(id)));
CREATE POLICY "students_insert_scoped" ON public.students FOR INSERT TO authenticated
  WITH CHECK (is_superadmin() OR current_user_role() IN ('admin','coordinator'));
CREATE POLICY "students_update_scoped" ON public.students FOR UPDATE TO authenticated
  USING (is_superadmin() OR (current_user_role() IN ('admin','coordinator') AND (school_id = current_user_school_id() OR school_id IS NULL)))
  WITH CHECK (is_superadmin() OR (current_user_role() IN ('admin','coordinator') AND (school_id = current_user_school_id() OR school_id IS NULL)));

CREATE POLICY "enrollments_select_scoped" ON public.enrollments FOR SELECT TO authenticated
  USING (is_superadmin() OR (current_user_role() IN ('admin','coordinator') AND section_in_school(section_id, current_user_school_id()))
         OR (current_user_role() = 'tutor' AND tutor_has_section(section_id)));
CREATE POLICY "enrollments_insert_scoped" ON public.enrollments FOR INSERT TO authenticated
  WITH CHECK (is_superadmin() OR (current_user_role() IN ('admin','coordinator') AND section_in_school(section_id, current_user_school_id())));
CREATE POLICY "enrollments_update_scoped" ON public.enrollments FOR UPDATE TO authenticated
  USING (is_superadmin() OR (current_user_role() IN ('admin','coordinator') AND section_in_school(section_id, current_user_school_id())))
  WITH CHECK (is_superadmin() OR (current_user_role() IN ('admin','coordinator') AND section_in_school(section_id, current_user_school_id())));
CREATE POLICY "enrollments_delete_scoped" ON public.enrollments FOR DELETE TO authenticated
  USING (is_superadmin() OR (current_user_role() IN ('admin','coordinator') AND section_in_school(section_id, current_user_school_id())));

CREATE POLICY "import_conflicts_select_scoped" ON public.import_conflicts FOR SELECT TO authenticated
  USING (is_superadmin() OR (current_user_role() IN ('admin','coordinator') AND section_id IS NOT NULL AND section_in_school(section_id, current_user_school_id())));
CREATE POLICY "import_conflicts_insert_scoped" ON public.import_conflicts FOR INSERT TO authenticated
  WITH CHECK (is_superadmin() OR (current_user_role() IN ('admin','coordinator') AND section_in_school(section_id, current_user_school_id())));
CREATE POLICY "import_conflicts_update_scoped" ON public.import_conflicts FOR UPDATE TO authenticated
  USING (is_superadmin() OR (current_user_role() IN ('admin','coordinator') AND section_id IS NOT NULL AND section_in_school(section_id, current_user_school_id())))
  WITH CHECK (is_superadmin() OR (current_user_role() IN ('admin','coordinator') AND section_id IS NOT NULL AND section_in_school(section_id, current_user_school_id())));

CREATE POLICY "tsa_select_scoped" ON public.tutor_section_assignments FOR SELECT TO authenticated
  USING (is_superadmin() OR tutor_id = auth.uid()
         OR (current_user_role() IN ('admin','coordinator') AND section_in_school(section_id, current_user_school_id())));
CREATE POLICY "tsa_insert_scoped" ON public.tutor_section_assignments FOR INSERT TO authenticated
  WITH CHECK (is_superadmin() OR (current_user_role() IN ('admin','coordinator') AND section_in_school(section_id, current_user_school_id())));
CREATE POLICY "tsa_delete_scoped" ON public.tutor_section_assignments FOR DELETE TO authenticated
  USING (is_superadmin() OR (current_user_role() IN ('admin','coordinator') AND section_in_school(section_id, current_user_school_id())));

CREATE POLICY "Users can read own profile" ON public.users FOR SELECT TO authenticated
  USING (auth.uid() = id);
CREATE POLICY "Admins and coordinators can read all users" ON public.users FOR SELECT TO authenticated
  USING (public.current_user_role() IN ('admin', 'coordinator'));
CREATE POLICY "users_update_scoped" ON public.users FOR UPDATE TO authenticated
  USING (
    is_superadmin()
    OR (current_user_role() IN ('admin','coordinator') AND school_id = current_user_school_id())
  )
  WITH CHECK (
    is_superadmin()
    OR (current_user_role() IN ('admin','coordinator') AND school_id = current_user_school_id())
  );

CREATE POLICY "Anyone can insert a login attempt" ON public.login_logs FOR INSERT TO anon, authenticated
  WITH CHECK (true);
CREATE POLICY "Admins and coordinators can read login logs" ON public.login_logs FOR SELECT TO authenticated
  USING (public.current_user_role() IN ('admin', 'coordinator'));
```

No `INSERT`/`DELETE` policies exist for `users` on purpose — account
creation only ever happens through the `create-user` Edge Function
(service role key, bypasses RLS).

## 3. Deploy the Edge Functions

```
supabase login
supabase init
supabase link --project-ref <your-project-ref>
supabase functions deploy create-user
supabase functions deploy bootstrap-admin
```

`create-user` now requires `school_id` on every request except a
superadmin creating another admin (send `school_id: null` for that
case). A school-bound admin/coordinator can only create users for their
own school — enforced server-side, not just client-side.

## 4. Point the app at this project

```
config-set-cloud-url <your-project-url>
config-set-cloud-anon-key <your-anon-key>
```

> Command names above are inferred from usage patterns elsewhere in the
> console, not confirmed against `config_commands.dart` directly.

## 5. Bootstrap the first (super)admin

```
bootstrap-admin cloud <admin-email> <admin full name>
```

Only works once per project. The bootstrapped admin has `school_id =
NULL`, making them a **superadmin** by definition — the account meant to
create schools and other admins. Temp password is **`password`**,
changed on first login.

## 6. Day-to-day commands

**Auth**

```
sign-in cloud <email> <password>
whoami
change-password <new password>
sign-out
```

**Users** (superadmin: any school, incl. school_id "-" for another admin;
school-bound admin/coordinator: own school only)

```
user-create <email> <admin|coordinator|tutor> <schoolId|-> <full name>
user-list
user-set-active <userId> <true|false>
```

**Schools** (create: superadmin only; list/update: own school, or all for superadmin)

```
school-create <schoolIdCode> <region|-> <division|-> <full school name>
school-list
school-update <id> <schoolIdCode> <region|-> <division|-> <full school name>
```

**Sections** (own school only, or all for superadmin)

```
section-create <schoolId> <schoolYear> <gradeLevel> <sectionName>
section-list
section-update <id> <schoolYear> <gradeLevel> <sectionName>
section-delete <id>
```

**Tutor-section assignments** (admin/coordinator, own school; superadmin: all)

```
assign-section <tutorId> <sectionId>
unassign-section <assignmentId>
list-tutor-sections <tutorId>
list-section-tutors <sectionId>
```

**Roster import** (admin/coordinator; requires sign-in)

```
import-preview <file.xlsx> <rowIndex>
import-students <file.xlsx>
list-conflicts
show-conflict <id>
resolve-conflict <id> <skip|update>
resolve-conflicts-all <skip|update>
```

`resolve-conflicts-all` is bulk, with no per-row review — testing
convenience only, not meant for unsupervised real use.

**Students, live from Supabase** (RLS-scoped — a tutor sees only their
assigned students)

```
student-list
student-list-section <sectionId>
```

**Local cache only** (offline reads — may lag behind Supabase)

```
list-sections
list-students <sectionId>
export-section <sectionId> <outputPath.csv>
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
- **Sf1Importer's Supabase write and local mirror aren't atomic** — a
  crash mid-import can leave the local cache stale (Supabase stays
  correct; local needs a manual re-sync in that case).
- **Multi-tutor concurrent-edit protection** (two co-assigned tutors on
  the same section editing the same data without clobbering each other)
  is deferred to the CRLA/ARAL assessment modules — not designed yet.
- **`resolve-conflicts-all`** applies its action to every pending
  conflict with no individual review — fine for seeded test data, risky
  if ever exposed for real admin use without a confirmation step.
