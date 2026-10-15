-- ARAL-Reading check-in tools (sample-files/ARAL/[FINAL] Check-Assessment
-- Tools for KS 2-3). Run after 20261016030000_aral_checkins.sql. Idempotent:
-- upserts tools on (key_stage, track, checkpoint) and items on
-- (tool_id, item_no), so a re-run updates the text and keys.
--
-- item_no runs 1..n over the whole tool; label keeps the printed number where
-- the sheet restarts numbering per part (Basic KS3 sessions 1-16). section is
-- the sheet's top-level part (sub-parts such as "A. Noun" are folded into
-- it); null where the sheet has no parts.
--
-- Keys follow the official answer keys, except (owner decision 2026-10-16):
--  * Plus KS3 sessions 17-32 #9: official key C (therefore); seeded A (so).
--  * Plus KS3 sessions 17-32 #19: official key D (informational); seeded B
--    (persuasive: the poster is a slogan).
-- Basic KS2 sessions 17-32 Sight Words: the key prints the words; seeded as the
-- letters of the word box (A and, B the, C you, D is, E a).

insert into public.aral_checkin_tools (key_stage, track, checkpoint, language, title) values
  ('ks2', 'basic', 16, 'filipino', 'ARAL-Reading Basic KS 2 Check-in Assessment, Sessions 1-16'),
  ('ks2', 'basic', 32, 'english',  'ARAL-Reading Basic KS 2 Check-in Assessment, Sessions 17-32'),
  ('ks3', 'basic', 16, 'filipino', 'ARAL-Reading Basic KS 3 Check-in Assessment, Sessions 1-16'),
  ('ks3', 'basic', 32, 'english',  'ARAL-Reading Basic KS 3 Check-in Assessment, Sessions 17-32'),
  ('ks2', 'plus',  16, 'english',  'ARAL-Reading Plus KS 2 Check-in Assessment, Sessions 1-16'),
  ('ks2', 'plus',  32, 'english',  'ARAL-Reading Plus KS 2 Check-in Assessment, Sessions 17-32'),
  ('ks3', 'plus',  16, 'english',  'ARAL-Reading Plus KS 3 Check-in Assessment, Sessions 1-16'),
  ('ks3', 'plus',  32, 'english',  'ARAL-Reading Plus KS 3 Check-in Assessment, Sessions 17-32')
on conflict (key_stage, track, checkpoint) do update
  set language = excluded.language, title = excluded.title;

insert into public.aral_checkin_items (tool_id, item_no, label, section, kind, answer_key, prompt)
select t.id, v.item_no, v.label, v.section, v.kind, v.answer_key, v.prompt
from (values
  -- Basic KS2, sessions 1-16 (Filipino) ------------------------------------------
  ('ks2', 'basic', 16, 1, null, 'I. Pagkilala sa Tunog', 'open', 'Larawang nagsisimula sa /m/', 'Nagsisimulang tunog sa /m/ (bilugan ang larawan)'),
  ('ks2', 'basic', 16, 2, null, 'I. Pagkilala sa Tunog', 'open', 'Larawang nagsisimula sa /s/', 'Nagsisimulang tunog sa /s/ (bilugan ang larawan)'),
  ('ks2', 'basic', 16, 3, null, 'I. Pagkilala sa Tunog', 'open', 'Larawang nagsisimula sa /a/', 'Nagsisimulang tunog sa /a/ (bilugan ang larawan)'),
  ('ks2', 'basic', 16, 4, null, 'I. Pagkilala sa Tunog', 'open', 'Larawang nagsisimula sa /i/', 'Nagsisimulang tunog sa /i/ (bilugan ang larawan)'),
  ('ks2', 'basic', 16, 5, null, 'I. Pagkilala sa Tunog', 'open', 'Larawang nagsisimula sa /g/', 'Nagsisimulang tunog sa /g/ (bilugan ang larawan)'),
  ('ks2', 'basic', 16, 6, null, 'II. Pagpapantig', 'open', 'mang-ga', 'Pantigin: mangga'),
  ('ks2', 'basic', 16, 7, null, 'II. Pagpapantig', 'open', 'sa-pa-tos', 'Pantigin: sapatos'),
  ('ks2', 'basic', 16, 8, null, 'II. Pagpapantig', 'open', 'bu-ko', 'Pantigin: buko'),
  ('ks2', 'basic', 16, 9, null, 'II. Pagpapantig', 'open', 'is-da', 'Pantigin: isda'),
  ('ks2', 'basic', 16, 10, null, 'II. Pagpapantig', 'open', 'ga-tas', 'Pantigin: gatas'),

  -- Basic KS2, sessions 17-32 (English) ------------------------------------------
  ('ks2', 'basic', 32, 1, null, 'I. Phonological Awareness', 'choice', 'D', 'Which word has an ''e'' sound?'),
  ('ks2', 'basic', 32, 2, null, 'I. Phonological Awareness', 'choice', 'A', 'Which word has a letter ''c'' that sounds as /k/?'),
  ('ks2', 'basic', 32, 3, null, 'I. Phonological Awareness', 'choice', 'A', 'Which word has a final /m/ sound?'),
  ('ks2', 'basic', 32, 4, null, 'I. Phonological Awareness', 'choice', 'D', 'Which word has a different beginning sound from the others?'),
  ('ks2', 'basic', 32, 5, null, 'I. Phonological Awareness', 'choice', 'A', 'Which word has a different final sound from the others?'),
  ('ks2', 'basic', 32, 6, null, 'I. Phonological Awareness', 'choice', 'B', 'How many /j/ sounds are in the sentence?'),
  ('ks2', 'basic', 32, 7, null, 'I. Phonological Awareness', 'choice', 'C', 'Which word begins with a /g/ sound?'),
  ('ks2', 'basic', 32, 8, null, 'II. Syllables', 'choice', 'A', 'Which among these words has 3 syllables?'),
  ('ks2', 'basic', 32, 9, null, 'II. Syllables', 'choice', 'D', 'Which word is not correctly divided into syllables?'),
  ('ks2', 'basic', 32, 10, null, 'II. Syllables', 'choice', 'C', 'Which phrase has 4 syllables?'),
  ('ks2', 'basic', 32, 11, null, 'III. Sight Words', 'choice', 'E', 'Claire ... finds ___ small black notebook (a)'),
  ('ks2', 'basic', 32, 12, null, 'III. Sight Words', 'choice', 'A', 'She picks up the notebook ___ opens it (and)'),
  ('ks2', 'basic', 32, 13, null, 'III. Sight Words', 'choice', 'B', 'She reads the notes in ___ first page (the)'),
  ('ks2', 'basic', 32, 14, null, 'III. Sight Words', 'choice', 'D', 'Clayton ___ Claire''s brother (is)'),
  ('ks2', 'basic', 32, 15, null, 'III. Sight Words', 'choice', 'C', '"Do ___ want to join us?" (you)'),
  ('ks2', 'basic', 32, 16, null, 'IV. Reading Comprehension', 'choice', 'D', 'Who loves art?'),
  ('ks2', 'basic', 32, 17, null, 'IV. Reading Comprehension', 'choice', 'B', 'Which among the materials did they NOT buy?'),
  ('ks2', 'basic', 32, 18, null, 'IV. Reading Comprehension', 'choice', 'C', 'Where did they buy the materials?'),
  ('ks2', 'basic', 32, 19, null, 'IV. Reading Comprehension', 'choice', 'C', 'Which event comes first?'),
  ('ks2', 'basic', 32, 20, null, 'IV. Reading Comprehension', 'choice', 'B', 'Which event happens last?'),

  -- Basic KS3, sessions 1-16 (Filipino); numbering restarts per part -------------
  ('ks3', 'basic', 16, 1, 'I.1', 'I. Paglinang ng Talasalitaan', 'open', 'medyas — telang nakalapat na pambalot sa paa', 'Larawan 1: salita at kahulugan'),
  ('ks3', 'basic', 16, 2, 'I.2', 'I. Paglinang ng Talasalitaan', 'open', 'sisiw — inakay ng inahing manok', 'Larawan 2: salita at kahulugan'),
  ('ks3', 'basic', 16, 3, 'I.3', 'I. Paglinang ng Talasalitaan', 'open', 'okra — bungang kulay berde, pahaba, matulis ang dulo, madulas ang laman', 'Larawan 3: salita at kahulugan'),
  ('ks3', 'basic', 16, 4, 'I.4', 'I. Paglinang ng Talasalitaan', 'open', 'susi — metal na ginagamit sa pagsasara o pagbubukas ng kandado', 'Larawan 4: salita at kahulugan'),
  ('ks3', 'basic', 16, 5, 'I.5', 'I. Paglinang ng Talasalitaan', 'open', 'buko — may malambot na laman at maraming sabaw na pwedeng inumin', 'Larawan 5: salita at kahulugan'),
  ('ks3', 'basic', 16, 6, 'II.1', 'II. Pagpapantig', 'open', 'ngi-pin', 'Pantigin: ngipin'),
  ('ks3', 'basic', 16, 7, 'II.2', 'II. Pagpapantig', 'open', 'pu-no', 'Pantigin: puno'),
  ('ks3', 'basic', 16, 8, 'II.3', 'II. Pagpapantig', 'open', 'ro-sas', 'Pantigin: rosas'),
  ('ks3', 'basic', 16, 9, 'II.4', 'II. Pagpapantig', 'open', 'da-li-ri', 'Pantigin: daliri'),
  ('ks3', 'basic', 16, 10, 'II.5', 'II. Pagpapantig', 'open', 'hag-dan', 'Pantigin: hagdan'),
  ('ks3', 'basic', 16, 11, 'III.1', 'III. Paggamit ng Sight Words', 'open', 'ang', 'Masaya (1) ___ umaga.'),
  ('ks3', 'basic', 16, 12, 'III.2', 'III. Paggamit ng Sight Words', 'open', 'mga', 'Inihanda niya ang kaniyang (2) ___ gamit'),
  ('ks3', 'basic', 16, 13, 'III.3', 'III. Paggamit ng Sight Words', 'open', 'sa', 'para (3) ___ paaralan'),
  ('ks3', 'basic', 16, 14, 'III.4', 'III. Paggamit ng Sight Words', 'open', 'ay', 'sila (4) ___ bumati nang magalang'),
  ('ks3', 'basic', 16, 15, 'III.5', 'III. Paggamit ng Sight Words', 'open', 'Ito', '(5) ___ ay nagbigay-saya sa kanilang klase.'),
  ('ks3', 'basic', 16, 16, 'IV.1', 'IV. Pag-unawa sa Binasa', 'choice', 'B', 'Alin sa mga larawan ang nagsisimula sa tunog na /v/?'),
  ('ks3', 'basic', 16, 17, 'IV.2', 'IV. Pag-unawa sa Binasa', 'choice', 'B', 'Ano ang naramdaman ni Jomar nang lumipad ang bola sa fence?'),
  ('ks3', 'basic', 16, 18, 'IV.3', 'IV. Pag-unawa sa Binasa', 'choice', 'C', 'Anong damdamin ni Wina sa sinabi niya kay Jomar?'),
  ('ks3', 'basic', 16, 19, 'IV.4', 'IV. Pag-unawa sa Binasa', 'open', null, 'Natutuhang salita: wastong baybay, unang tunog at kahulugan (sariling sagot)'),
  ('ks3', 'basic', 16, 20, 'IV.5', 'IV. Pag-unawa sa Binasa', 'open', null, 'Sariling ideya o opinyon tungkol sa binasa (sariling sagot)'),

  -- Basic KS3, sessions 17-32 (English) ------------------------------------------
  ('ks3', 'basic', 32, 1, null, 'I. Forming Words', 'choice', 'D', 'Change the initial sound of "make" to /t/'),
  ('ks3', 'basic', 32, 2, null, 'I. Forming Words', 'choice', 'A', 'Change the initial sound of "hide" to /r/'),
  ('ks3', 'basic', 32, 3, null, 'I. Forming Words', 'choice', 'D', 'Change the final sound of "dam" to /y/'),
  ('ks3', 'basic', 32, 4, null, 'I. Forming Words', 'choice', 'C', 'Change the final sound of "mat" to /p/'),
  ('ks3', 'basic', 32, 5, null, 'I. Forming Words', 'choice', 'A', 'Remove the initial sound of "farm"'),
  ('ks3', 'basic', 32, 6, null, 'I. Forming Words', 'choice', 'A', 'Change the underlined sound in "lace" to /k/'),
  ('ks3', 'basic', 32, 7, null, 'I. Forming Words', 'choice', 'A', 'Word with a consonant blend: "My friend loves red flowers."'),
  ('ks3', 'basic', 32, 8, null, 'I. Forming Words', 'choice', 'D', 'Word with a consonant blend: "Joyce reads her book before she sleeps at night."'),
  ('ks3', 'basic', 32, 9, null, 'II. Word Concept', 'choice', 'B', 'Vocabulary: meaning of "panic"'),
  ('ks3', 'basic', 32, 10, null, 'II. Word Concept', 'choice', 'B', 'Vocabulary: meaning of "struggling"'),
  ('ks3', 'basic', 32, 11, null, 'II. Word Concept', 'choice', 'A', 'Sight words: Emily learned about Recycling ___ class.'),
  ('ks3', 'basic', 32, 12, null, 'II. Word Concept', 'choice', 'B', 'Sight words: to take care ___ the environment.'),
  ('ks3', 'basic', 32, 13, null, 'II. Word Concept', 'choice', 'E', 'Sight words: There ___ many ways to do it.'),
  ('ks3', 'basic', 32, 14, null, 'II. Word Concept', 'choice', 'C', 'Sight words: turn materials ___ are old into something new.'),
  ('ks3', 'basic', 32, 15, null, 'II. Word Concept', 'choice', 'D', 'Sight words: "It ___ very useful," said Emily.'),
  ('ks3', 'basic', 32, 16, null, 'III. Reading Comprehension', 'choice', 'B', 'Who is the new student in class?'),
  ('ks3', 'basic', 32, 17, null, 'III. Reading Comprehension', 'choice', 'B', 'What does Robert always bring?'),
  ('ks3', 'basic', 32, 18, null, 'III. Reading Comprehension', 'choice', 'D', 'How does Robert''s classmate feel about him?'),
  ('ks3', 'basic', 32, 19, null, 'III. Reading Comprehension', 'choice', 'D', 'Why does the classmate say that Robert loves to read?'),
  ('ks3', 'basic', 32, 20, null, 'III. Reading Comprehension', 'choice', 'A', 'Why does Robert love to read?'),

  -- Plus KS2, sessions 1-16 -------------------------------------------------------
  ('ks2', 'plus', 16, 1, null, 'I. Content Words', 'choice', 'D', 'Noun in "She is a good writer"'),
  ('ks2', 'plus', 16, 2, null, 'I. Content Words', 'choice', 'B', 'Sentence that uses "ring" as a noun'),
  ('ks2', 'plus', 16, 3, null, 'I. Content Words', 'choice', 'A', 'Sentence that does not use "tip" as a noun'),
  ('ks2', 'plus', 16, 4, null, 'I. Content Words', 'choice', 'D', 'Verb in "I listen to audiobooks every day."'),
  ('ks2', 'plus', 16, 5, null, 'I. Content Words', 'choice', 'D', 'Sentence with a verb in its simple past form'),
  ('ks2', 'plus', 16, 6, null, 'I. Content Words', 'choice', 'D', 'Sentence that uses "train" as a verb'),
  ('ks2', 'plus', 16, 7, null, 'I. Content Words', 'choice', 'B', 'Adjective in "She enjoys the lovely view of the city."'),
  ('ks2', 'plus', 16, 8, null, 'I. Content Words', 'choice', 'A', 'Sentence that has an adjective'),
  ('ks2', 'plus', 16, 9, null, 'II. Synonym & Antonym', 'choice', 'A', 'Synonym of "doubtful"'),
  ('ks2', 'plus', 16, 10, null, 'II. Synonym & Antonym', 'choice', 'C', 'Synonym of "discomfort"'),
  ('ks2', 'plus', 16, 11, null, 'II. Synonym & Antonym', 'choice', 'A', 'Antonym of "complicated"'),
  ('ks2', 'plus', 16, 12, null, 'III. Reading Comprehension', 'choice', 'C', 'The Hunter and the Horseman: who offered to buy the hare?'),
  ('ks2', 'plus', 16, 13, null, 'III. Reading Comprehension', 'choice', 'B', 'The Hunter and the Horseman: where does the story happen?'),
  ('ks2', 'plus', 16, 14, null, 'III. Reading Comprehension', 'choice', 'B', 'The Hunter and the Horseman: describe the horseman'),
  ('ks2', 'plus', 16, 15, null, 'III. Reading Comprehension', 'choice', 'C', 'The Hunter and the Horseman: why did the horseman readily agree?'),
  ('ks2', 'plus', 16, 16, null, 'III. Reading Comprehension', 'choice', 'A', 'The Bear and the Travellers: who are the characters?'),
  ('ks2', 'plus', 16, 17, null, 'III. Reading Comprehension', 'choice', 'D', 'The Bear and the Travellers: what problem do they face?'),
  ('ks2', 'plus', 16, 18, null, 'III. Reading Comprehension', 'choice', 'D', 'The Bear and the Travellers: how does the problem get solved?'),
  ('ks2', 'plus', 16, 19, null, 'III. Reading Comprehension', 'choice', 'C', 'The Bear and the Travellers: how does the story begin?'),
  ('ks2', 'plus', 16, 20, null, 'III. Reading Comprehension', 'choice', 'B', 'The Bear and the Travellers: how does the story end?'),

  -- Plus KS2, sessions 17-32 (no parts) -------------------------------------------
  ('ks2', 'plus', 32, 1, null, null, 'choice', 'A', 'A character who helps others without being asked is ___'),
  ('ks2', 'plus', 32, 2, null, null, 'choice', 'D', 'Which shows a character''s feeling?'),
  ('ks2', 'plus', 32, 3, null, null, 'choice', 'C', 'Marga hid behind the door: what can you say about Marga?'),
  ('ks2', 'plus', 32, 4, null, null, 'choice', 'B', 'Eli shared his toy: what trait does Eli show?'),
  ('ks2', 'plus', 32, 5, null, null, 'choice', 'B', 'Which line proves the character is brave?'),
  ('ks2', 'plus', 32, 6, null, null, 'choice', 'C', 'Mary''s wrecked bike: what can we infer about Mary?'),
  ('ks2', 'plus', 32, 7, null, null, 'choice', 'C', 'Expression for relating a story to your own life'),
  ('ks2', 'plus', 32, 8, null, null, 'choice', 'D', 'Purpose of making a personal connection to a story'),
  ('ks2', 'plus', 32, 9, null, null, 'choice', 'D', '"...remind me of our life in the province": what are you showing?'),
  ('ks2', 'plus', 32, 10, null, null, 'choice', 'D', 'Typhoon: which sentence shows the effect?'),
  ('ks2', 'plus', 32, 11, null, null, 'choice', 'A', 'Signal phrase for cause and effect'),
  ('ks2', 'plus', 32, 12, null, null, 'choice', 'B', 'Surprise quiz: what could happen next?'),
  ('ks2', 'plus', 32, 13, null, null, 'choice', 'D', 'Open books, busy writing: what can you conclude?'),
  ('ks2', 'plus', 32, 14, null, null, 'choice', 'C', 'Lia and the broken toy car: what can you conclude about Lia?'),
  ('ks2', 'plus', 32, 15, null, null, 'choice', 'C', 'What Is Climate Change?: what does climate change mean?'),
  ('ks2', 'plus', 32, 16, null, null, 'choice', 'B', 'What Is Climate Change?: how much has the Earth warmed?'),
  ('ks2', 'plus', 32, 17, null, null, 'choice', 'D', 'What Is Climate Change?: statement showing the effects are not mild'),
  ('ks2', 'plus', 32, 18, null, null, 'choice', 'A', 'What Is Climate Change?: detail supporting that weather gets harder to predict'),
  ('ks2', 'plus', 32, 19, null, null, 'choice', 'D', 'How to Make a Fruit Salad: what type of text is this?'),
  ('ks2', 'plus', 32, 20, null, null, 'choice', 'D', 'How to Make a Fruit Salad: what can you conclude?'),
  ('ks2', 'plus', 32, 21, null, null, 'choice', 'A', 'Describing an apple: what type of text is this?'),
  ('ks2', 'plus', 32, 22, null, null, 'choice', 'B', 'Describing an apple: which sense is described the most?'),
  ('ks2', 'plus', 32, 23, null, null, 'choice', 'C', 'Describing an apple: how does the author feel about apples?'),

  -- Plus KS3, sessions 1-16 (no parts; the "MOSY" file has the same items) ---------
  ('ks3', 'plus', 16, 1, null, null, 'choice', 'C', 'The prefix pre- means ___'),
  ('ks3', 'plus', 16, 2, null, null, 'choice', 'D', 'What does "endless" mean?'),
  ('ks3', 'plus', 16, 3, null, null, 'choice', 'C', 'Meaning of "inspiring"'),
  ('ks3', 'plus', 16, 4, null, null, 'choice', 'A', 'Best reference for a difficult word'),
  ('ks3', 'plus', 16, 5, null, null, 'choice', 'D', 'Meaning of "serene"'),
  ('ks3', 'plus', 16, 6, null, null, 'choice', 'A', 'What does "unspoken" mean?'),
  ('ks3', 'plus', 16, 7, null, null, 'choice', 'A', 'What does "bravery" mean?'),
  ('ks3', 'plus', 16, 8, null, null, 'choice', 'B', 'Why Does the Ocean Have Waves?: topic of the passage'),
  ('ks3', 'plus', 16, 9, null, null, 'choice', 'A', 'Why Does the Ocean Have Waves?: main cause of most waves'),
  ('ks3', 'plus', 16, 10, null, null, 'choice', 'D', 'Why Does the Ocean Have Waves?: how waves are formed'),
  ('ks3', 'plus', 16, 11, null, null, 'choice', 'D', 'Why Does the Ocean Have Waves?: how tsunamis are formed'),
  ('ks3', 'plus', 16, 12, null, null, 'choice', 'D', 'Why Does the Ocean Have Waves?: best summary'),
  ('ks3', 'plus', 16, 13, null, null, 'choice', 'B', 'The Lion and the Mouse: how does the mouse feel when caught?'),
  ('ks3', 'plus', 16, 14, null, null, 'choice', 'B', 'The Lion and the Mouse: meaning of "grateful"'),
  ('ks3', 'plus', 16, 15, null, null, 'choice', 'C', 'The Lion and the Mouse: why does the lion laugh?'),
  ('ks3', 'plus', 16, 16, null, null, 'choice', 'D', 'The Lion and the Mouse: predict what happens after the mouse is freed'),
  ('ks3', 'plus', 16, 17, null, null, 'choice', 'A', 'The Lion and the Mouse: conclusion about the mouse'),
  ('ks3', 'plus', 16, 18, null, null, 'choice', 'C', 'The Lion and the Mouse: message or lesson'),
  ('ks3', 'plus', 16, 19, null, null, 'choice', 'B', 'The Lion and the Mouse: sentence supporting "kindness is rewarded"'),
  ('ks3', 'plus', 16, 20, null, null, 'choice', 'D', 'The Lion and the Mouse: lesson the lion learns'),

  -- Plus KS3, sessions 17-32 (no parts) -------------------------------------------
  ('ks3', 'plus', 32, 1, null, null, 'choice', 'A', 'Point of view: "I felt nervous when I stood in front of the class."'),
  ('ks3', 'plus', 32, 2, null, null, 'choice', 'B', 'Point of view: "You open the box and find a shining key inside."'),
  ('ks3', 'plus', 32, 3, null, null, 'choice', 'C', 'Author''s purpose: "Join our campaign! Plant a tree today..."'),
  ('ks3', 'plus', 32, 4, null, null, 'choice', 'B', 'Author''s purpose: the Pacific Ocean is the largest and deepest...'),
  ('ks3', 'plus', 32, 5, null, null, 'choice', 'C', 'Author''s purpose: Ryan laughed as the big labrador chased its tail...'),
  ('ks3', 'plus', 32, 6, null, null, 'choice', 'A', 'Type of text: the Philippines has approximately 7,000 islands...'),
  ('ks3', 'plus', 32, 7, null, null, 'choice', 'D', 'Grandmother''s open windows: best cause and effect'),
  ('ks3', 'plus', 32, 8, null, null, 'choice', 'A', 'Power outage, very hot, ___ we went to a convenience store'),
  ('ks3', 'plus', 32, 9, null, null, 'choice', 'A', 'Practiced hard every day, ___ we won (official key C; corrected to A)'),
  ('ks3', 'plus', 32, 10, null, null, 'choice', 'B', 'Victor was promoted to the advanced group because ___'),
  ('ks3', 'plus', 32, 11, null, null, 'choice', 'B', '___ of the heavy rain, the river rose three feet'),
  ('ks3', 'plus', 32, 12, null, null, 'choice', 'B', '"Dogs are probably the greatest pets...": type of statement'),
  ('ks3', 'plus', 32, 13, null, null, 'choice', 'B', '"Everyone is buying the new iPhone 17...": propaganda technique'),
  ('ks3', 'plus', 32, 14, null, null, 'choice', 'C', 'Famous actor endorsing a chicken meal: propaganda technique'),
  ('ks3', 'plus', 32, 15, null, null, 'choice', 'C', 'One main benefit of recycling'),
  ('ks3', 'plus', 32, 16, null, null, 'choice', 'A', 'Text that tells a story with characters, setting and plot'),
  ('ks3', 'plus', 32, 17, null, null, 'choice', 'B', 'Main purpose of an informational text'),
  ('ks3', 'plus', 32, 18, null, null, 'choice', 'C', 'A recipe for adobong baboy is what type of text?'),
  ('ks3', 'plus', 32, 19, null, null, 'choice', 'B', 'Poster "We never know the worth of water..." (official key D; corrected to B)'),
  ('ks3', 'plus', 32, 20, null, null, 'choice', 'D', 'A good conclusion based on the clues shown')
) as v(key_stage, track, checkpoint, item_no, label, section, kind, answer_key, prompt)
join public.aral_checkin_tools t
  on t.key_stage = v.key_stage and t.track = v.track and t.checkpoint = v.checkpoint
on conflict (tool_id, item_no) do update
  set label = excluded.label, section = excluded.section, kind = excluded.kind,
      answer_key = excluded.answer_key, prompt = excluded.prompt;
