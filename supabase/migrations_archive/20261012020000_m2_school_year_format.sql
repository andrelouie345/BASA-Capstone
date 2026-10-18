-- M2: one canonical school_year format, "YYYY-YYYY" (consecutive years).
-- Idempotent: safe to run in the Supabase SQL Editor more than once.
--
-- school_year was free text and is part of three unique keys
-- (sections, enrollments, crla_assessments). The dev project held
-- "2026-2027", "2025 - 2026" and "2026" side by side, so the same section
-- could be created twice under different spellings. The app now normalizes
-- through normalizeSchoolYear() (lib/core/services/normalizers.dart); these
-- CHECKs stop anything else from getting in.
--
-- If a CHECK fails to add, a row still has a non-canonical value: the whole
-- transaction rolls back, nothing is half-applied.

begin;

-- 1. Rewrite spacing / dash / "SY" variants of a two-year span.
update public.sections
   set school_year = regexp_replace(school_year,
         '^\s*(?:S\.?\s*Y\.?\s*)?(\d{4})\s*[-/‐-―]\s*(\d{4})\s*$', '\1-\2', 'i')
 where school_year !~ '^\d{4}-\d{4}$';
update public.enrollments
   set school_year = regexp_replace(school_year,
         '^\s*(?:S\.?\s*Y\.?\s*)?(\d{4})\s*[-/‐-―]\s*(\d{4})\s*$', '\1-\2', 'i')
 where school_year !~ '^\d{4}-\d{4}$';
update public.crla_assessments
   set school_year = regexp_replace(school_year,
         '^\s*(?:S\.?\s*Y\.?\s*)?(\d{4})\s*[-/‐-―]\s*(\d{4})\s*$', '\1-\2', 'i')
 where school_year !~ '^\d{4}-\d{4}$';

-- 2. One-off: dev section 1 ("Funny", school TEST-001) was stored as a bare
--    "2026" and has no enrollments. Owner-confirmed value below.
update public.sections set school_year = '2026-2027'
 where id = 1 and school_year = '2026';

-- 3. Enforce the shape. CASE keeps the ::int casts from running on bad text.
alter table public.sections drop constraint if exists sections_school_year_format;
alter table public.sections add constraint sections_school_year_format check (
  case when school_year ~ '^\d{4}-\d{4}$'
       then right(school_year, 4)::int = left(school_year, 4)::int + 1
       else false end);

alter table public.enrollments drop constraint if exists enrollments_school_year_format;
alter table public.enrollments add constraint enrollments_school_year_format check (
  case when school_year ~ '^\d{4}-\d{4}$'
       then right(school_year, 4)::int = left(school_year, 4)::int + 1
       else false end);

alter table public.crla_assessments drop constraint if exists crla_assessments_school_year_format;
alter table public.crla_assessments add constraint crla_assessments_school_year_format check (
  case when school_year ~ '^\d{4}-\d{4}$'
       then right(school_year, 4)::int = left(school_year, 4)::int + 1
       else false end);

commit;
