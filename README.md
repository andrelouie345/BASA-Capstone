# BASA — Backend Setup Guide

This covers standing up the backend (users, schools, roster, CRLA, Phil-IRI,
ARAL) for a **new deployment** and bootstrapping its first superadmin. It assumes a fresh Supabase project —
cloud or self-hosted LAN — with nothing configured yet.

This backend is multi-school capable by design: one Supabase project can
host many schools (a shared regional deployment), or you can run one
project per school if a region prefers full isolation — nothing about the
schema or app forces either choice.

> **⚠ Hard requirement: keep the database and every device on the same BASA
> release.** Each release is an app version plus the migrations it needs. A
> school or division that hosts its own database must apply a release's
> migrations when it installs that app version, and update every device when
> the release notes say so. Running mixed versions makes pulls fail, refuses
> work entered on outdated devices, or has outdated devices work by old rules.
> See *Keeping BASA up to date* below before going live.

> **Schema status (2026-10-18).** The whole database schema is one file,
> `supabase/migrations/20261018040000_baseline.sql`, generated from the live
> project and checked to rebuild it exactly. The 29 older migrations it
> replaces are kept in `supabase/migrations_archive/` as history only; they
> cannot build a new database. Content (regions, check-in tools, IRIP targets,
> Phil-IRI passages) comes from `supabase/seeds/`.

## 1. Provision the backend

Create a new Supabase cloud project (supabase.com) or stand up a
self-hosted LAN instance. Note its **URL** and **anon key**.

## 2. Apply the schema

### 2a. Baseline

Run `supabase/migrations/20261018040000_baseline.sql` in the new project's SQL
editor (or `supabase db push` from a linked project). It creates every table,
view, function, trigger, RLS policy and privilege BASA uses. It is idempotent,
so running it twice does no harm.

An **existing** project that already has this schema (the original BASA
project) runs nothing here.

### 2b. Newer migrations

Run every file in `supabase/migrations/` that is **newer** than the baseline,
in filename order (the timestamps sort them). As of 2026-10-19 they are
`20261018050000` (ARAL readability log), `20261019010000` and `20261019020000`
(SRP classes), `20261019030000` (assessment calendar), `20261019040000`
(report settings), `20261019050000` (calendar round pairing),
`20261019060000` (ARAL idle session days; app update required: no) and
`20261020010000` (migrations ledger `basa_migrations`, for the version check at
sign-in; app update required: no). Each is idempotent. Do **not** run
`supabase/migrations_archive/`.

**Rule for every new migration:** its header says `App update required on all
devices: yes/no`, and its **last statement** records it in the ledger, with the
same yes/no:

```sql
insert into public.basa_migrations (id, name, app_update_required)
values ('<id>', '<name>', <true|false>) on conflict (id) do nothing;
```

The same commit adds `'<id>': '<name>'` to `lib/core/release.dart`. Without the
ledger row, every app built with that migration refuses to sign in to the
database ("the database is older than this BASA app").

### 2c. Seeds (content)

Run in the SQL editor, in this order (each is idempotent; `supabase db reset`
also loads them, see `supabase/config.toml`):

1. `supabase/seeds/regions.sql` — the 18 Philippine regions (`schools.region_id`)
2. `supabase/seeds/aral_checkin_tools.sql` — ARAL check-in assessment tools
3. `supabase/seeds/aral_irip_targets.sql` — IRIP weekly reading targets
4. `supabase/seeds/phil_iri_graded_passages_pool.sql` — the Phil-IRI passage
   pool used for assessments (active)
5. `supabase/seeds/phil_iri_pool_social_media_spectrum.sql` — one more pool
   passage (Grade 8, MOSY)
6. optional, older sets kept inactive: `phil_iri_2018_english.sql`,
   `phil_iri_jhs_2024_english_pretest.sql`, `phil_iri_jhs_2024_english_posttest.sql`

ARAL learning materials are **not** seeded and their files are not stored in
Supabase; see *ARAL learning materials* below.

### Deliberately missing policies

An absent policy means "denied":

- `users` INSERT/DELETE — accounts are created only through the
  `create-user` Edge Function (service role key, bypasses RLS). An
  INSERT policy would let an admin/coordinator write profile rows
  directly, around that function's checks. Accounts are deactivated with
  `is_active`, not deleted: deleting the `public.users` row would leave
  the `auth.users` login behind (the cascade only runs the other way).
- `login_logs` UPDATE/DELETE — logs are append-only.
- `tutor_section_assignments` UPDATE — an assignment is removed and re-added,
  not edited.
- `schools` DELETE is allowed to the superadmin only (`schools_delete_superadmin`).

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

Use the project's **anon / publishable** key only — never the `service_role`
key. Either set it at runtime in the console (saved to
`<data dir>/supabase_config.json`):

```
config-set-cloud-url <your-project-url>
config-set-cloud-key <your-anon-key>
config-set-lan-url <lan-url>          (self-hosted LAN Supabase, optional)
config-set-lan-key <lan-anon-key>
config-show
```

or bake defaults into a build. They are used only when the device has no
saved config yet (nothing is hardcoded in the source):

```
flutter build <target> --dart-define=BASA_CLOUD_URL=<url> --dart-define=BASA_CLOUD_KEY=<anon-key>
dart run -DBASA_CLOUD_URL=<url> -DBASA_CLOUD_KEY=<anon-key> lib/console/main.dart
```

(`BASA_LAN_URL` / `BASA_LAN_KEY` likewise.)

## 5. Bootstrap the first (super)admin

```
bootstrap-admin cloud <admin-email> <admin full name>
```

Only works once per project. The bootstrapped admin has `school_id =
NULL`, making them a **superadmin** by definition — the account meant to
create schools and other admins. The command prints a random **temporary
password once**; it must be changed on first login.

## 6. Verify the policies

Run this after applying the schema, and again any time a table or policy
is touched. There should be no policy you didn't write, and no `true`
qualifier except the `regions` SELECT (the region list is public reference
data).

```sql
-- every live policy
select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
order by tablename, cmd, policyname;

-- RLS switched on for every table?
select c.relname, c.relrowsecurity
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r'
order by c.relname;
```

Watch for leftover "allow all" / "authenticated users can read X"
placeholder policies — they have caused false-passing tests before
(schools, students, testTable).

## 7. Day-to-day commands

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

## ARAL learning materials (files are not stored in BASA)

BASA recommends ARAL learning materials but never stores the files, so any
school can run its own Supabase at little or no cost. The material set (DepEd
ARAL-Reading learner's workbooks and tutor's guides for KS1-KS3, and the
SHARP / Alpha-Phonics materials) is over 1 GB, with several files above
Supabase's 50 MB per-file limit on the free plan.

**Installing the files.** The reading coordinator gets the files (they are
free resources) and either:

- shares them through Google Drive (a folder per program is easiest), or
- copies them into the installation package, so every device has them.

**Cataloguing them.** Each catalog entry names the document and where to find
it; nothing else is uploaded:

```
aral-material-add <region|schoolId> <foundational|ks1|ks2|ks3> <basic|plus|any> <learner|tutor|supplementary> <English|Filipino> "<title>" [grades=7-10] ["file=<file name>"] [link=<url>]
aral-material-set <id|"title"> file "<file name>"
aral-material-set <id|"title"> link <url>
```

The superadmin keeps the region-wide catalog; a school's admin/coordinator adds
the school's own materials.

**Keeping links alive.** Google Drive links can expire or move. Each school's
coordinator can set their own link for any material their school sees,
including region-wide ones; their learners' recommendations then use it:

```
aral-material-school-link <id|"title"> <schoolId> <url>      (or "-" to remove it)
```

Recommendations (`aral-recommend <enrollmentId>`, `aral-recommend-section
<sectionId> <schoolYear>`) show each document's title, file name and the link
that applies to the learner's school, and work offline once the catalog is on
the device (`pull-cloud`).

## Keeping BASA up to date (hard requirement)

A BASA **release** is an app version plus the database migrations it needs.
The database and every device must run the same release.

**What does NOT need an update:** everyday data. Calendar windows, done
thresholds, ARAL settings, users, schools, sections, learners and assessments
are changed through the app at any time.

**What does:** a new release. In this order:

1. **Apply the release's new migrations first** (section 2b), in filename
   order, before or together with installing the new app. A new app on an
   older database fails wherever it needs something new; for example,
   `pull-cloud` stops when a table it copies doesn't exist yet.
2. **Update every device** when the release notes say so. An older app on a
   newer database is safe only for additions (new tables or columns: it
   ignores them). When a release **changes rules**, every device must update.
   Examples: an instrument's assessment rounds, a value that becomes required,
   a renamed or removed column. Until a device is updated:
   - its `pull-cloud` rolls back and keeps its old copy (nothing is lost, but
     it can't get new data);
   - work entered on it can be refused by the database;
   - it keeps computing with the old rules.

What protects the data: the database checks refuse rows that break the
current rules, so an outdated device cannot store invalid data in the cloud.
What it does NOT protect against is an outdated device working by old rules
until it is updated. That is why updating is a requirement, not a
recommendation.

**Before going live, decide who applies migrations** on a self-hosted
database, and **how devices get updated** (installation package, app store,
or manual install). Re-check this every school year.

**The version check at sign-in** compares the migrations the app was built for
(`version-app` in the console lists them) with the database's `basa_migrations`
ledger. Every online sign-in (cloud and LAN) runs it:

- **The database is older than the app**: sign-in is refused and the message
  lists the files to apply, in order. The person who manages the database
  applies them (section 2b), then sign in again. A database without the ledger
  at all asks for `20261020010000_basa_migrations.sql` and any earlier file
  not yet applied.
- **The app is older and the database has a change marked "app update
  required"**: sign-in is refused ("this BASA app is too old"). Update BASA on
  that device.
- **The app is older but the database only has additions**: sign-in works,
  with a note to update when you can.
- **The ledger can't be read** (a connection error after the password was
  accepted, or a broken select permission): sign-in is refused; try again, and
  if it repeats, check the ledger's select policy.

`version-check` in the console runs the same comparison for the signed-in
database at any time (e.g. after migrations were applied mid-session).
Refused sign-ins are recorded in the login log with a `version check: ...`
reason.

## Known gaps (not yet built)

- **The baseline is generated, not hand-written** — after a schema change,
  add a new migration file (newer than the baseline) rather than editing the
  baseline. To refresh the baseline later, re-dump the live schema
  (`pg_dump --schema-only --schema=public --no-owner --no-privileges`, session
  pooler connection) and regenerate it.
- **Login is always online** — no offline/cached fallback exists.
- **Cloud login-log sync has no retry** — an attempt logged locally while
  offline never gets flushed to the cloud once connectivity returns.
- **`login_logs` INSERT is open to `anon` for failed attempts** — required
  so failed attempts can be logged before sign-in (`login_logs_insert_own`:
  anon may insert only failed attempts without a user; a signed-in user only
  their own). Side effect: anyone holding the anon key can insert fake
  *failed* attempts. Accepted trade-off (reading real data would still
  require compromising an account).
- **Unknown-email login attempts are superadmin-only** — they have no
  `user_id`, so no school can claim them; school-bound admins never see
  them.
- **Orphaned students** (`school_id` NULL, never enrolled) can be updated
  by any admin/coordinator but deleted only by a superadmin.
- **Local cache isn't scoped per user yet** — a second user signing in on
  a shared device is intended to replace the local cache (with a warning
  to the user), but this isn't implemented.
- **No separate admin/tutor builds** — role gating is currently
  client-side/UI-level only, not enforced by excluding code from the
  build.
- **LAN/self-hosted profile is untested end-to-end.**
- **The version check runs only at online sign-in** — a database migrated
  while someone is signed in is noticed at their next sign-in (or with
  `version-check`). There is no offline sign-in yet; sync will decide what it
  trusts.
- **Sf1Importer's Supabase write and local mirror aren't atomic** — a
  crash mid-import can leave the local cache stale (Supabase stays
  correct; local needs a manual re-sync in that case).
- **Multi-tutor concurrent-edit protection** (two co-assigned tutors on
  the same section editing the same data without clobbering each other)
  is deferred to the CRLA/ARAL assessment modules — not designed yet.
- **`resolve-conflicts-all`** applies its action to every pending
  conflict with no individual review — fine for seeded test data, risky
  if ever exposed for real admin use without a confirmation step.
- **No user hard-delete** — accounts are deactivated (`is_active`), never
  removed; a real delete would need an Edge Function that also removes
  the `auth.users` row.
