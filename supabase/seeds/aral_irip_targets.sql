-- ARAL-Reading IRIP reading targets (from IRIP_ARAL-Reading Basic and
-- Plus_v09122025.docx). Run after 20261016010000_aral_irip.sql. Idempotent:
-- upserts on (program, strand, seq), so a re-run updates the text.
--  * basic_ks23: KS2-3 Basic, Filipino and English in parallel (focus = the
--    phonological awareness focus, then the letter focus and sight words).
--  * plus_ks2 / plus_ks3: one target per week, each a group of skills (one per line).

insert into public.aral_irip_targets (program, strand, seq, focus, letter_focus, sight_words, skills) values
  ('basic_ks23', 'filipino', 1, 'Word Concept (print carries meaning; word boundaries)', 'M, S, A, I, O, B, E',
   'N/A (Focus on oral naming and print awareness)', null),
  ('basic_ks23', 'filipino', 2, 'Alliteration', 'U, T, K, L, N, G', 'Ang, Mga, Sa, Ito, Ay', null),
  ('basic_ks23', 'filipino', 3, 'Syllable Manipulation (clapping, deleting, blending)', 'Ng, P, R, D, H, N',
   'Ako, Ikaw, Si, At, May', null),
  ('basic_ks23', 'filipino', 4, 'Phoneme Manipulation (onset-rime, segment/blend)', 'W, Y, Mga Letrang Banyaga',
   'Phrase/Sentence Reading using previous 10 words', null),
  ('basic_ks23', 'english', 1, 'Word Concept (1:1 correspondence; tracking print)', 'a, m, t, s, i, f, d',
   'N/A (focus on letter-sound fluency)', null),
  ('basic_ks23', 'english', 2, 'Alliteration', 'r, o, g, l, h, u, c', 'a, the, and, you, is', null),
  ('basic_ks23', 'english', 3, 'Syllable Manipulation (clap, blend, segment)', 'b, n, k, v, e, w, j',
   'he, she, we, to, on', null),
  ('basic_ks23', 'english', 4, 'Phoneme Manipulation + Blends + CVCe',
   'Consonant Blends (bl, cl, st, etc.), CVCe (e.g., cake, bike)', 'in, of, that, was, are', null),
  ('basic_ks23', 'english', 5, 'Phoneme Manipulation + Diphthongs', 'Diphthongs (e.g., oi, ou)',
   'Phrase/Sentence Reading using 10 sight words', null),

  ('plus_ks2', 'main', 1, null, null, null,
   'Identifying high-frequency words accurately
Identifying roots of high-frequency words (nouns, verbs, adjectives)'),
  ('plus_ks2', 'main', 2, null, null, null,
   'Identifying synonyms and antonyms
Using vocabulary in a new context
Identifying words with different functions (noun, verb, adjectives)'),
  ('plus_ks2', 'main', 3, null, null, null,
   'Reading words accurately and automatically according to patterns
Reading sentences with appropriate speed, accuracy, and expression'),
  ('plus_ks2', 'main', 4, null, null, null,
   'Noting important story elements (character, setting, events)
Sequencing events
Identifying problem and solution'),
  ('plus_ks2', 'main', 5, null, null, null,
   'Inferring character feelings and traits
Relating story events to personal experiences'),
  ('plus_ks2', 'main', 6, null, null, null,
   'Identifying cause and effect of events
Predicting possible endings
Drawing conclusions'),
  ('plus_ks2', 'main', 7, null, null, null,
   'Noting significant details
Summarizing'),
  ('plus_ks2', 'main', 8, null, null, null,
   'Identifying text types
Drawing conclusions (spiral review)'),

  ('plus_ks3', 'main', 1, null, null, null,
   'Using context clues to understand unfamiliar words
Using structural analysis (prefix, suffix, root)
Identifying literal and implied meanings of words
Using general references (print/online)'),
  ('plus_ks3', 'main', 2, null, null, null,
   'Self-assessing fluency
Reading aloud with proper pacing and expression
Using non-verbal cues to enhance fluency
Using context to confirm word meaning and self-correct errors during reading, including rereading when necessary'),
  ('plus_ks3', 'main', 3, null, null, null,
   'Noting important story elements (characters, setting, conflict, resolution)
Identifying author''s/speaker''s point of view
Sequencing events
Identifying plot type
Summarizing story events'),
  ('plus_ks3', 'main', 4, null, null, null,
   'Making inferences
Making predictions
Drawing conclusions
Identifying the theme'),
  ('plus_ks3', 'main', 5, null, null, null,
   'Noting important information through outlining (topic, main idea, supporting details)
Identifying author''s purpose
Identifying text types
Making generalizations'),
  ('plus_ks3', 'main', 6, null, null, null,
   'Analyzing figures of speech to clarify meaning
Analyzing sound devices
Differentiating fantasy from reality'),
  ('plus_ks3', 'main', 7, null, null, null,
   'Distinguishing fact from opinion
Identifying propaganda techniques
Making summaries
Noting information through outlining (topic, main idea, details)'),
  ('plus_ks3', 'main', 8, null, null, null,
   'Identifying visual/multimedia elements
Deriving meaning based on the visual/multimedia elements
Identifying real or make-believe, fact or non-fact images
Evaluating cultural appropriateness of visual/multimedia elements
Creating a visual/multimedia text drawn from visual elements learned')
on conflict (program, strand, seq) do update
  set focus = excluded.focus, letter_focus = excluded.letter_focus,
      sight_words = excluded.sight_words, skills = excluded.skills;

select program, strand, count(*) as targets from public.aral_irip_targets group by 1, 2 order by 1, 2;
