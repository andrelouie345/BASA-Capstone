-- The 18 Philippine regions (reference data for schools.region_id and
-- crla_stories.region_id). Idempotent: existing rows are left as they are.
-- ids 1-18 follow this fixed order (e.g. 7 = NCR, 13 = Region X); the app's
-- local copy (lib/core/data/local/local_database.dart) uses the same list.
insert into public.regions (id, code, name) values
  (1, 'Region I', 'Ilocos Region'),
  (2, 'Region II', 'Cagayan Valley'),
  (3, 'Region III', 'Central Luzon'),
  (4, 'Region IV-A', 'CALABARZON'),
  (5, 'Region IV-B', 'MIMAROPA'),
  (6, 'Region V', 'Bicol Region'),
  (7, 'NCR', 'National Capital Region'),
  (8, 'CAR', 'Cordillera Administrative Region'),
  (9, 'Region VI', 'Western Visayas'),
  (10, 'Region VII', 'Central Visayas'),
  (11, 'Region VIII', 'Eastern Visayas'),
  (12, 'Region IX', 'Zamboanga Peninsula'),
  (13, 'Region X', 'Northern Mindanao'),
  (14, 'Region XI', 'Davao Region'),
  (15, 'Region XII', 'SOCCSKSARGEN'),
  (16, 'Region XIII', 'Caraga'),
  (17, 'BARMM', 'Bangsamoro Autonomous Region in Muslim Mindanao'),
  (18, 'NIR', 'Negros Island Region')
on conflict (id) do nothing;
