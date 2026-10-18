# Archived migrations (history only)

These 29 migrations (2026-10-12 to 2026-10-18) were applied, in order, to the
original BASA project. They are kept for history and review only.

**Do not run them on a new project.** They assume tables, views and functions
that were first created by hand before migrations were tracked, so they cannot
build a database from scratch. A new project runs
`supabase/migrations/20261018040000_baseline.sql` instead (the full schema as
of 2026-10-18, which already contains everything these files did), then any
newer migration, then the seeds — see README.md, section 2.
