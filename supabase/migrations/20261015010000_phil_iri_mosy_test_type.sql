-- Phil-IRI: a passage's test type can also be 'mosy'. Idempotent: safe to run
-- in the Supabase SQL Editor more than once.
--
-- Owner decision (2026-10-15, from the reading coordinator): MOSY uses its own
-- passages from the same pool as BOSY/EOSY, never the BOSY (pre) or EOSY
-- (post) ones. The test type says which round a passage is for within its
-- collection: 'pre' = BOSY, 'mosy' = MOSY 1-3, 'post' = EOSY, null = any round
-- (school collections, below-grade passages). Rounds are not filtered by test
-- type yet; that is the next piece.
--
-- RLS: unchanged. Only a CHECK constraint changes; phil_iri_passages keeps its
-- policies (read via phil_iri_collection_readable, write via
-- phil_iri_collection_writable) and no view reads test_type.

alter table public.phil_iri_passages
  drop constraint if exists phil_iri_passages_test_type_check;
alter table public.phil_iri_passages
  add constraint phil_iri_passages_test_type_check
  check (test_type in ('pre', 'mosy', 'post'));
