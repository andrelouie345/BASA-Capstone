-- "Phil-IRI Graded Passages (Level 2-10)": the graded-passage pool (booklet) used for
-- BOSY, MOSY and EOSY. Source: sample-files/Phil-IRI/MOSY (student questionnaire,
-- teacher scoresheet, answer key).
--
-- One region-wide, prescribed collection, seeded INACTIVE. Switch over after the
-- round filter is in place: phil-iri-collection-activate <this id> on, and the
-- "Phil-IRI JHS 2024" collection off (the 2018 one is already off). Re-running
-- this file never changes is_active of an existing collection.
--
-- Test type = the round a passage is for (reading coordinator, 2026-10-15):
--   'pre'  = BOSY: the G7-G10 "Pre" passages (2024 pretest)
--   'post' = EOSY: the G7-G10 "Post" passages (2024 posttest)
--   'mosy' = MOSY 1-3: G7 A1-D2 (the 2018 level-7 passages) and the MoSY passages
--            for G8-G10
--   null   = any round: levels 2-6 (sets A-D); any grade-level passage will do.
-- set_code is the booklet's code (A..D, A1..D2, RCH2, ...); null for Pre/Post.
--
-- Texts and questions: as already seeded and reviewed (2018 and 2024 collections)
-- where the booklet has the same passage; the booklet's own texts and questions
-- for the new ones ("What's for Lunch?" = the On Market Day text with new
-- questions; five MoSY passages). Answer keys: the BOOKLET's (owner, 2026-10-15),
-- except Yawning and Sneezing whose booklet keys are broken. Each passage notes
-- where its key differs from the manual's.
--
-- Left out: "The Social Media Spectrum" (MoSYG08-RCH13). Its printed questions
-- quote "The Impact of Social Media on Communication" (made the world smaller,
-- exchanges, Messenger/Viber/WhatsApp), not this text.
--
-- Word counts: whitespace words of the stored text (PhilIriPassage.words). The
-- MoSY counts match the printed ones, except "The Evolution of Mystery" (509;
-- printed 510 counts a free-standing "-", stored here as an em dash attached to
-- the word before it, like every dash in these seeds).
--
-- Idempotent: run it in the SQL Editor as often as needed; existing rows are
-- left alone. Contains nothing that bypasses RLS: created_by stays null when run
-- without a signed-in user (SQL Editor), as the stamp trigger allows.

do $seed$
declare
  c bigint;
  p bigint;
begin
  select id into c from public.phil_iri_collections
   where school_id is null and lower(name) = lower($t$Phil-IRI Graded Passages (Level 2-10)$t$);
  if c is null then
    insert into public.phil_iri_collections
      (school_id, name, description, is_prescribed, is_grade_leveled, has_comprehension, is_active)
    values (null, $t$Phil-IRI Graded Passages (Level 2-10)$t$,
            'Graded-passage pool for BOSY (pre), MOSY (mosy) and EOSY (post): levels 2-6 sets A-D (any round), Grades 7-10 Pre/MoSY/Post.',
            true, true, true, false)
    returning id into c;
  end if;

  -- G2A: Pam's Cat (level 2, any round; 35 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 2 and title = $t$Pam's Cat$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', null, $t$A$t$, 2, $t$Pam's Cat$t$,
            $t$What can cats do?
In the story, let's find out what Pam's cat can do.$t$,
            $t$Pam has a cat. It is on the bed. It can nap. It can sit. "Oh no!" says Pam. "The cat fell off the bed!" Is the cat sad? No. It is on the mat.$t$,
            35)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Who has a pet?$t$,
          jsonb_build_array($t$Pat$t$, $t$Pam$t$, $t$Paz$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What is her pet?$t$,
          jsonb_build_array($t$dog$t$, $t$pig$t$, $t$cat$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Why did Pam say "Oh no!"?$t$,
          jsonb_build_array($t$She was mad.$t$, $t$She was happy.$t$, $t$She was worried.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Why did she feel this way?$t$,
          jsonb_build_array($t$Her cat can do tricks.$t$, $t$Her cat made a mess.$t$, $t$Her cat might be hurt.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$How do we know that the cat is ok?$t$,
          jsonb_build_array($t$It is on the bed.$t$, $t$It is on the mat.$t$, $t$It has a rat.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;

  -- G2B: A Hot Day (level 2, any round; 37 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 2 and title = $t$A Hot Day$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', null, $t$B$t$, 2, $t$A Hot Day$t$,
            $t$What do you do to feel cool on a hot day?
What did characters in the story do to feel cool on a hot day?$t$,
            $t$The sun is up. "Is it a hot day, Matt?" asks Sal.
"Yes, it is," says Matt. Sal gets her fan. Matt gets his hat.
Sal and Matt go out to play. Sal and Matt have fun.$t$,
            37)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Who are the children in the story?$t$,
          jsonb_build_array($t$Sam and Matt$t$, $t$Sal and Max$t$, $t$Matt and Sal$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What kind of day was it?$t$,
          jsonb_build_array($t$a sunny day$t$, $t$a cloudy day$t$, $t$a rainy day$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$What did the little girl do so that she will not feel hot?$t$,
          jsonb_build_array($t$She stayed inside.$t$, $t$She got a hat.$t$, $t$She got a fan.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$What did the little boy do so that he will not feel hot?$t$,
          jsonb_build_array($t$He stayed inside.$t$, $t$He got a hat.$t$, $t$He got a fan.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$What is the message of the story?$t$,
          jsonb_build_array($t$We can have fun on a hot day.$t$, $t$We can have fun on a cool day.$t$, $t$We can have fun on a cloudy day.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;

  -- G2C: Al's Bag (level 2, any round; 28 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 2 and title = $t$Al's Bag$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', null, $t$C$t$, 2, $t$Al's Bag$t$,
            $t$What can you put in a basket?
In the story, let's find out what Al had in his basket.$t$,
            $t$Al has a bag. It has a mat. It has buns. It has bananas. But it has ants too! "Ants! Ants!" says Al. Al lets the bag go.$t$,
            28)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$What is the name of the boy in the story?$t$,
          jsonb_build_array($t$Al$t$, $t$Alf$t$, $t$Ants$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What does he have in his bag?$t$,
          jsonb_build_array($t$a mat$t$, $t$an apple$t$, $t$an orange$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$What will he do?$t$,
          jsonb_build_array($t$have a nap$t$, $t$have a party$t$, $t$have a snack$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Why does he let his bag go?$t$,
          jsonb_build_array($t$He is afraid.$t$, $t$He is glad.$t$, $t$He is mad.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Which sentence tells us why it is a good idea for the boy to let go of his bag?$t$,
          jsonb_build_array($t$So the ants cannot get the food$t$, $t$So the ants cannot bite him$t$, $t$So the ants will be free$t$), 'b')
  on conflict (passage_id, question_no) do nothing;

  -- G2D: Nat Takes a Nap (level 2, any round; 27 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 2 and title = $t$Nat Takes a Nap$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', null, $t$D$t$, 2, $t$Nat Takes a Nap$t$,
            $t$Who helps you fall asleep?
In the story, let's find out who helped Nat fall asleep.$t$,
            $t$Nat will nap. He will nap on his bed.
But Nat wet the bed. He cannot nap. Nat is sad. Mama gets Nat. Nat has his nap.$t$,
            27)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Who will nap?$t$,
          jsonb_build_array($t$Matt$t$, $t$Nat$t$, $t$Pat$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$Where did he want to nap?$t$,
          jsonb_build_array($t$in the bed$t$, $t$up the bed$t$, $t$on the bed$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Why was he not able to take a nap?$t$,
          jsonb_build_array($t$Mama was not there.$t$, $t$It was not time to nap.$t$, $t$He did not want to get wet.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Who helped him have his nap?$t$,
          jsonb_build_array($t$Mama$t$, $t$Papa$t$, $t$No one$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$What did he feel when Mama got him?$t$,
          jsonb_build_array($t$glad$t$, $t$sad$t$, $t$afraid$t$), 'a')
  on conflict (passage_id, question_no) do nothing;

  -- G3A: Summer Fun (level 3, any round; 57 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 3 and title = $t$Summer Fun$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', null, $t$A$t$, 3, $t$Summer Fun$t$,
            $t$What do you do when it is summer time?
In the story, let's find out what the children will do in the summer.$t$,
            $t$"Let's have some fun this summer," says Leo. "Let's swim in the river," says Lina.
"Let's get some star apples from the tree," says Leo. "Let's pick flowers," says Lina.
"That is so much fun!" says Mama. "But can you help me dust the shelves too?"
"Yes, we can Mama," they say. "Helping can be fun too!"$t$,
            57)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Who were talking to each other?$t$,
          jsonb_build_array($t$Lita and Lito$t$, $t$Lina and Lino$t$, $t$Lina and Leo$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What were they talking about?$t$,
          jsonb_build_array($t$what to do during the summer$t$, $t$what to have during the summer$t$, $t$what to wear during the summer$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$The children in the story could be _______$t$,
          jsonb_build_array($t$brother and sister$t$, $t$neighbors$t$, $t$cousins$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Which of these will they do if they are hungry?$t$,
          jsonb_build_array($t$pick flowers$t$, $t$pick guavas$t$, $t$go swimming$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Doing something "fun" means ______________.$t$,
          jsonb_build_array($t$doing something in the summer$t$, $t$doing something in the house$t$, $t$doing something that we like$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Which these is the best example of being helpful?$t$,
          jsonb_build_array($t$picking flowers$t$, $t$cleaning up$t$, $t$swimming$t$), 'b')
  on conflict (passage_id, question_no) do nothing;

  -- G3B: A Rainy Day (level 3, any round; 66 words)
  -- Key: booklet differs from the manual at Q3 c->a (manual -> booklet).
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 3 and title = $t$A Rainy Day$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', null, $t$B$t$, 3, $t$A Rainy Day$t$,
            $t$Which games do you play inside the house on a rainy day?
In the story, let's find out what game they will play.$t$,
            $t$Nina and Ria are looking out the window. "I do not like getting wet in the rain," says Nina.
"What can we do?" asks Ria. "We can play house," says Nina. "Or we can play tag," says Ria. "Okay, let's play tag. You're it!" says Nina. Nina runs from Ria and bumps a lamp.
"Oh no!" says Nina. "We must not play tag in the house."$t$,
            66)
    returning id into p;
  end if;
  -- CHECK: Q1 asks what RIA does not like; in the passage it is Nina who does not like getting wet. Kept as printed.
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$What is it that Ria does not like?$t$,
          jsonb_build_array($t$playing tag$t$, $t$playing house$t$, $t$getting wet in the rain$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What does Nina want to do?$t$,
          jsonb_build_array($t$play tag$t$, $t$play house$t$, $t$get wet in the rain$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Who wants to play tag?$t$,
          jsonb_build_array($t$Ria$t$, $t$Nina$t$, $t$Ria and Nina$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$What is "tag?"$t$,
          jsonb_build_array($t$a card game$t$, $t$a video game$t$, $t$a running game$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Why wasn't it a good idea to play tag in the house?$t$,
          jsonb_build_array($t$Something might break$t$, $t$Someone might get tired$t$, $t$Something might get lost$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Which word tells what Ria and Nina should be?$t$,
          jsonb_build_array($t$careless$t$, $t$careful$t$, $t$curious$t$), 'b')
  on conflict (passage_id, question_no) do nothing;

  -- G3C: Ben's Store (level 3, any round; 57 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 3 and title = $t$Ben's Store$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', null, $t$C$t$, 3, $t$Ben's Store$t$,
            $t$What do you buy at the store?
In the story, let's find out what is in Ben's store.$t$,
            $t$Ben has his own store. "Do you sell eggs?" asks Mel.
"Yes, come in," says Ben. "Do you sell milk?" asks Dante.
"Yes, come in," says Ben. "Do you sell hats?" asks Lala. "No, we do not sell hats," says Ben. "But you can come in and have a look." Lala goes in. She gets a banana.$t$,
            57)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Who is the main character in the story?$t$,
          jsonb_build_array($t$Ben$t$, $t$Lala$t$, $t$Mel$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What does he have?$t$,
          jsonb_build_array($t$a school$t$, $t$a store$t$, $t$a hat$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$What is the store for?$t$,
          jsonb_build_array($t$a place used for fixing things$t$, $t$a place used for selling things$t$, $t$a place used for keeping things$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$What do you think does it sell?$t$,
          jsonb_build_array($t$Ben's store sells hats.$t$, $t$Ben's store sells toys.$t$, $t$Ben's store sells food.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Why was it important for Lala to go in and "have a look?"$t$,
          jsonb_build_array($t$to find out what she can sell$t$, $t$to find out what she can buy$t$, $t$to find out what she can keep$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Which of these words best describes Ben?$t$,
          jsonb_build_array($t$helpful$t$, $t$greedy$t$, $t$giving$t$), 'a')
  on conflict (passage_id, question_no) do nothing;

  -- G3D: Waiting for Her Sister (level 3, any round; 58 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 3 and title = $t$Waiting for Her Sister$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', null, $t$D$t$, 3, $t$Waiting for Her Sister$t$,
            $t$What do you do if you are picked up late from school?
In the story, let's find out what Mara did when she was picked up late.$t$,
            $t$Mara sat by the school gate. It was the end of the day. Mara looked at her watch.
"Where is Ate Mila?" she asked. Mara looked at her watch again. At last, Mila has come to pick her up. "Let's go home. Mama said it's time for dinner," says Mila. "I am glad you are here," says Mara.$t$,
            58)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$What did Mara want to do?$t$,
          jsonb_build_array($t$go home$t$, $t$go to school$t$, $t$go on a long trip$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$Why was Mara by the school gate?$t$,
          jsonb_build_array($t$She could not carry her big school bag.$t$, $t$She was waiting for her sister.$t$, $t$She wanted to know the time.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$What part of the day was it?$t$,
          jsonb_build_array($t$the start of the school day$t$, $t$the middle of the school day$t$, $t$the end of the school day$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$What does the phrase "pick up" mean?$t$,
          jsonb_build_array($t$to get from the floor$t$, $t$to fetch someone and bring them home$t$, $t$to deliver something from one place to another$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Why did Mara keep looking at her watch?$t$,
          jsonb_build_array($t$She wanted to check for the time.$t$, $t$She was worried that it was getting late.$t$, $t$She wanted to know the time that Mila left.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Which of these is the best thing for Mila to do so that Mara will not be so worried? Mila should ________________.$t$,
          jsonb_build_array($t$come on time$t$, $t$give her a big hug$t$, $t$bring a friend along$t$), 'a')
  on conflict (passage_id, question_no) do nothing;

  -- G4A: Get Up, Jacky! (level 4, any round; 67 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 4 and title = $t$Get Up, Jacky!$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', null, $t$A$t$, 4, $t$Get Up, Jacky!$t$,
            $t$What makes you get up in the morning?
In the story, let's find out what made the child get up.$t$,
            $t$"Ring! Ring!" rang the clock. But Jacky did not get up.
"Wake up Jacky! Time for school," yelled Mom. And yet Jacky did not get up.
"Beep! Beep!" honked the horn of the bus. Jacky still laid snug on the bed.
Suddenly, a rooster crowed out loud and sat on the window sill.
Jacky got up and said with cheer, "I will get up now. I will!"$t$,
            67)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Who is the main character in our story?$t$,
          jsonb_build_array($t$Jock$t$, $t$Jicky$t$, $t$Jacky$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$Why did the main character need to wake up early?$t$,
          jsonb_build_array($t$to get to school on time$t$, $t$to get to work on time$t$, $t$to get to bed on time$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$What woke the character up?$t$,
          jsonb_build_array($t$the ringing of the alarm clock$t$, $t$the crowing of the rooster$t$, $t$Mom's yelling$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$What did the character think as he/she "laid snug" on the bed?$t$,
          jsonb_build_array($t$"I do not want to get up yet."$t$, $t$"I do not want to be late today."$t$, $t$"I want to be extra early today."$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$What does it mean to say something "with cheer?"$t$,
          jsonb_build_array($t$We say it sadly.$t$, $t$We say it happily.$t$, $t$We say it with fear.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Which of these statements fits the story?$t$,
          jsonb_build_array($t$Jacky liked being woken up by a clock.$t$, $t$Jacky liked being woken up by a bus horn.$t$, $t$Jacky liked being woken up by a rooster.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- G4B: Waiting for the Peddler (level 4, any round; 69 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 4 and title = $t$Waiting for the Peddler$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', null, $t$B$t$, 4, $t$Waiting for the Peddler$t$,
            $t$What do the peddlers in your neighborhood shout out loud?
In the story, let's find out what the peddler says out loud.$t$,
            $t$Mama was feeling sick. "Lisa, I cannot make you a snack," she said. "Can you watch out for the peddler while I rest?"
"Yes Mama," Lisa answered. Soon, a man shouted, "Taho! Taho!" Lisa ran. "Two cups please," she said.
Lisa paid the man. She got one cup of taho and gave the other to Mama. "Thank you, Lisa. I feel much better now," said Mama.
"You're welcome, Mama!"$t$,
            69)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$What is it that Mama could NOT do?$t$,
          jsonb_build_array($t$She could not go out.$t$, $t$She could not make Lisa a snack.$t$, $t$She could not wait for the peddler.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$Which of the following did NOT happen in the story?$t$,
          jsonb_build_array($t$Lisa went out to buy taho.$t$, $t$Lisa waited for the peddler.$t$, $t$Lisa made a snack for Mama.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Which of the following words best describes Lisa?$t$,
          jsonb_build_array($t$obedient$t$, $t$resourceful$t$, $t$hardworking$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Which statement tells us what a peddler can do?$t$,
          jsonb_build_array($t$A peddler sells snacks.$t$, $t$A peddler visits the sick.$t$, $t$A peddler brings medicine.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$When we "watch out" for something or someone, we ____?$t$,
          jsonb_build_array($t$look at something$t$, $t$wait for something$t$, $t$go away from something$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Which statement best fits the story?$t$,
          jsonb_build_array($t$It is good to visit the sick.$t$, $t$It is best to buy from a peddler.$t$, $t$Those who help us sometimes need help, too.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- G4C: Anansi's Web (level 4, any round; 86 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 4 and title = $t$Anansi's Web$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', null, $t$C$t$, 4, $t$Anansi's Web$t$,
            $t$Why does a spider make itself a web?
In the story, let's find out why a spider makes a web.$t$,
            $t$Anansi was tired of her web. So one day, she said "I will go live with the ant."
Now, the ant lived in a small hill. Once in the hill Anansi cried, "This place is too dark! I will go live with the bees."
When she got to the beehive, Anansi cried, "This place is too hot and sticky! I will go live with the beetle."
But on her way to beetle's home she saw her web. "Maybe a web is the best place after all."$t$,
            86)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Where does Anansi live?$t$,
          jsonb_build_array($t$in a beehive$t$, $t$in a web$t$, $t$in a hill$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What was her problem?$t$,
          jsonb_build_array($t$She was tired of living in other insects' homes.$t$, $t$She was tired of living in a web.$t$, $t$She was tired of being a spider.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Which of the following happened last?$t$,
          jsonb_build_array($t$She went to beetle's house.$t$, $t$She went back to the web.$t$, $t$She went to the beehive.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$What would she have said at beetle's home?$t$,
          jsonb_build_array($t$"This place is not for me."$t$, $t$"This place can be better."$t$, $t$"This place is exactly like my web."$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Which of the following solved her problem?$t$,
          jsonb_build_array($t$She tried out other insects' homes.$t$, $t$She stayed at home all day.$t$, $t$She made a new home.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$At the end of the story, which statement do you think is she going to say?$t$,
          jsonb_build_array($t$"My home is your home."$t$, $t$"Homes should be shared."$t$, $t$"There's no place like home."$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- G4D: What's for Lunch? (level 4, any round; 80 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 4 and title = $t$What's for Lunch?$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', null, $t$D$t$, 4, $t$What's for Lunch?$t$,
            null,
            $t$Every Saturday, Manuel goes to market with his father, Mang Ador. They always pass by Aling Juaning's stall to buy meat. They go to Mang Tinoy's for fresh vegetables. They also visit Aling Tita's seafood section.
Whenever Mang Ador buys something, Manuel always tries to predict what his father will cook for lunch. Today Mang Ador bought tamarind, tomatoes, string beans, radish, and shrimp.
"I know what we will have for lunch," says Manuel happily. Can you guess it, too?$t$,
            80)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Who does Manuel go to the market with every Saturday?$t$,
          jsonb_build_array($t$his mother$t$, $t$his friend$t$, $t$his father$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What do they buy from Mang Tinoy's stall?$t$,
          jsonb_build_array($t$meat$t$, $t$fresh vegetables$t$, $t$seafood$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Which of these is one thing that Mang Ador bought on this trip?$t$,
          jsonb_build_array($t$chicken and potatoes$t$, $t$tamarind and shrimp$t$, $t$fish and mangoes$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$What does Manuel try to predict whenever his father buys something?$t$,
          jsonb_build_array($t$how much it will cost$t$, $t$what his father will cook$t$, $t$which stall they will go to next$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Based on what Mang Ador bought, what dish do you think they will have for lunch?$t$,
          jsonb_build_array($t$Adobo$t$, $t$Sinigang$t$, $t$Fried Chicken$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$In the story, what is the best meaning of the word "stall"?$t$,
          jsonb_build_array($t$a large grocery store$t$, $t$a table or small shop selling goods$t$, $t$to wait or stop moving$t$), 'b')
  on conflict (passage_id, question_no) do nothing;

  -- G5A: Frog's Lunch (level 5, any round; 101 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 5 and title = $t$Frog's Lunch$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', null, $t$A$t$, 5, $t$Frog's Lunch$t$,
            $t$What do frogs eat?
In the story, what did the frog eat?$t$,
            $t$One day, a frog sat on a lily pad, still as a rock. A fish swam by.
"Hello, Mr. Frog! What are you waiting for?" "I am waiting for my lunch," said the frog.
"Oh, good luck!" said the fish and swam away. Then, a duck waddled by.
"Hello Mr. Frog! What are you waiting for?" "I am waiting for my lunch," said the frog. "Oh, good luck!" said the duck and waddled away.
Then a bug came buzzing by. "Hello Mr. Frog! What are you doing?" asked the bug.
"I'm having my lunch! Slurp!" said the frog. Mr. Frog smiled.$t$,
            101)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Who is the main character in the story?$t$,
          jsonb_build_array($t$the bug$t$, $t$the duck$t$, $t$the fish$t$, $t$the frog$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What was he doing?$t$,
          jsonb_build_array($t$resting on a lily pad$t$, $t$chatting with a bug$t$, $t$hunting for his food$t$, $t$waiting for the rain$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$In what way was he able to get his lunch?$t$,
          jsonb_build_array($t$He was able to fool the fish.$t$, $t$He was able to fool the duck.$t$, $t$He was able to fool the rock.$t$, $t$He was able to fool the bug.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Why should the frog be "still as a rock?"$t$,
          jsonb_build_array($t$so that he will not scare the other animals away$t$, $t$so that he can catch his lunch$t$, $t$so that the other animals will think he is friendly$t$, $t$so that the fish will say nice things about him$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Which of these words describe the duck?$t$,
          jsonb_build_array($t$patient$t$, $t$eager$t$, $t$curious$t$, $t$careful$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Which of these words describe Mr. Frog?$t$,
          jsonb_build_array($t$patient$t$, $t$eager$t$, $t$curious$t$, $t$careful$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$Which of these characteristics would have helped the bug?$t$,
          jsonb_build_array($t$being patient$t$, $t$being eager$t$, $t$being curious$t$, $t$being careful$t$), 'd')
  on conflict (passage_id, question_no) do nothing;

  -- G5B: The Cow and the Carabao (level 5, any round; 152 words)
  -- Key: booklet differs from the manual at Q4 b->d (manual -> booklet).
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 5 and title = $t$The Cow and the Carabao$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', null, $t$B$t$, 5, $t$The Cow and the Carabao$t$,
            $t$What do cows and carabaos look like?
In the story, let's find out how the cow and carabao ended up looking the way they do.$t$,
            $t$Long ago, a farmer had a carabao and a cow. The carabao was bigger but the cow worked just as hard.
One day the farmer said, "I can get more from my farm if my carabao works all day and my cow works all night." This went on for a month till finally, the carabao cried, "It is just too hot to work all day!" "Want to go for a swim?" asked the cow. "It will cool you off." The carabao happily agreed. They went off without the farmer's consent.
Before swimming, they hung their skins on a tree branch. But it wasn't long till the farmer went looking for them. Upon seeing the farmer, they rushed to put on their skins. In their rush, the carabao had worn the cow's skin and the cow had worn the carabao's skin.
From then on, cows have sagging skin while carabaos have tight skin.$t$,
            152)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$At the beginning of the story, what was one major difference between the cow and the carabao?$t$,
          jsonb_build_array($t$The carabao was bigger than the cow.$t$, $t$The cow had sagging skin while the carabao had tight skin.$t$, $t$The carabao had sagging skin while the cow had tight skin.$t$, $t$The carabao worked at night while the cow worked in the day.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What did the farmer decide one day?$t$,
          jsonb_build_array($t$The cow and the carabao will work together.$t$, $t$The cow and the carabao should not leave the farm.$t$, $t$The carabao will work in the day while the cow will work at night.$t$, $t$The cow will work in the day while the carabao will work at night.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$What word describes the farmer in the story?$t$,
          jsonb_build_array($t$kind$t$, $t$cruel$t$, $t$grumpy$t$, $t$hardworking$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$How did the farmer's decision affect the cow and the carabao?$t$,
          jsonb_build_array($t$They did not have time to rest.$t$, $t$They hardly saw each other.$t$, $t$They did not eat enough.$t$, $t$They were always tired.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$What does the phrase "without consent" mean?$t$,
          jsonb_build_array($t$did not have permission$t$, $t$was not informed$t$, $t$has not rested$t$, $t$did not know$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Which of the following events happened last?$t$,
          jsonb_build_array($t$The carabao cried out that it was so hot.$t$, $t$The cow and the carabao decided to swim.$t$, $t$The farmer came while the animals were swimming.$t$, $t$The cow and the carabao hurriedly put on their skins.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$What kind of story is this?$t$,
          jsonb_build_array($t$myth$t$, $t$parable$t$, $t$legend$t$, $t$fairy tale$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- G5C: Pedrito's Snack (level 5, any round; 144 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 5 and title = $t$Pedrito's Snack$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', null, $t$C$t$, 5, $t$Pedrito's Snack$t$,
            $t$What is your favorite snack? With whom did you share it?
In the story, what did Pedrito do with his favorite snack? With whom did he share it?$t$,
            $t$The bell rang. "It's snack time!" Pedrito shouted and ran out of the room. He sat on a bench under a tall tree.
In Pedrito's lunch bag were three soft buns. He got the first one and took a bite. "Mmmm," said Pedrito. Just then, a sparrow sat on the bench. It was looking at him. Pedrito didn't mind. He went on and finished his bun.
Then Pedrito got his second bun. He took a big bite and said "Mmmm!" The sparrow was still looking at him. It also moved closer. But still, Pedrito did not mind. He went on and finished his bun.
Finally, Pedrito got his last bun. He was about to take a bite when the sparrow flew up to his shoulder. Pedrito smiled, cut the bun in two and said to himself, "I think someone also likes bread and butter."$t$,
            144)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$What was Pedrito excited about?$t$,
          jsonb_build_array($t$having his favorite snack$t$, $t$going to the bench$t$, $t$being with the birds$t$, $t$finding a friend$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$Which of the statements explains the sentence, "Pedrito didn't mind."$t$,
          jsonb_build_array($t$Pedrito was not thinking.$t$, $t$Pedrito was not bothered.$t$, $t$Pedrito did not want to think.$t$, $t$Pedrito did not want to be bothered.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Which of these was NOT mentioned in the story?$t$,
          jsonb_build_array($t$The sparrow looked at the bread.$t$, $t$The sparrow sat down on the bench.$t$, $t$The sparrow moved closer to Pedrito.$t$, $t$The sparrow flew onto Pedrito's shoulder.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$What does the word 'finished' mean in the phrase "finished his bun?"$t$,
          jsonb_build_array($t$The bun was eaten.$t$, $t$The bun was prepared.$t$, $t$The bun was thrown away.$t$, $t$The bun was already spoiled.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Why was the sparrow looking at him?$t$,
          jsonb_build_array($t$It wanted to be a pet.$t$, $t$It wanted to watch Pedrito as he ate.$t$, $t$It wanted to have a share of the bun.$t$, $t$It wanted to listen more closely to Pedrito.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Why did Pedrito have to break the third bun in two?$t$,
          jsonb_build_array($t$So that he can eat the bun in two bites.$t$, $t$So that he can cut up the bun some more.$t$, $t$So that he can share it with the sparrow.$t$, $t$So that he can save the other half for later.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$Which of the following sentences best shows what Pedrito thought of at the end of the story?$t$,
          jsonb_build_array($t$"Sharing is only true among friends."$t$, $t$"Ask and you shall receive."$t$, $t$"One good turn deserves another."$t$, $t$"Something good is even better when shared."$t$), 'd')
  on conflict (passage_id, question_no) do nothing;

  -- G5D: Amy's Good Deed (level 5, any round; 106 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 5 and title = $t$Amy's Good Deed$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', null, $t$D$t$, 5, $t$Amy's Good Deed$t$,
            $t$What are examples of good deeds?
In the story, what was Amy's good deed?$t$,
            $t$Amy loves walking home from school to see the colors of the leaves and listen to the birds sing. But one day, she heard a soft cry. It came from under a bush. "Should I go near?" Amy wondered. As it grew louder, Amy decided she must help the poor thing.
Amy crept closer and held her arm out. Just when she was about to reach out, she saw a pair of eyes and heard a loud "Hissss!!!!" She also felt a sharp pain. "Ouch!" Amy cried. Her arm had four long scratch marks. Amy was upset. She really thought she was doing a good deed.$t$,
            106)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$What does Amy love to do?$t$,
          jsonb_build_array($t$catching animals$t$, $t$listening to the trees$t$, $t$walking home from school$t$, $t$seeing the colors of the birds$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What did she find unusual?$t$,
          jsonb_build_array($t$the thorny bush$t$, $t$the cry of an animal$t$, $t$the colors of the leaves$t$, $t$the singing of the birds$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$What did Amy want to do?$t$,
          jsonb_build_array($t$She wanted to save the animal.$t$, $t$She wanted to scare the animal.$t$, $t$She wanted to hurt the animal.$t$, $t$She wanted to keep the animal.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$What happened when she tried to help?$t$,
          jsonb_build_array($t$She was yelled at.$t$, $t$She was scratched.$t$, $t$She was bitten.$t$, $t$She was pulled forward.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Why did the animal react that way?$t$,
          jsonb_build_array($t$The animal was getting ready to attack.$t$, $t$The animal wanted to be friends.$t$, $t$The animal was scared of Amy.$t$, $t$The animal wanted to play.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$What for Amy is a "good deed?"$t$,
          jsonb_build_array($t$a surprise$t$, $t$a harmful act$t$, $t$a brave action$t$, $t$an act of kindness$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$Which phrase best describes Amy?$t$,
          jsonb_build_array($t$a hardworking girl$t$, $t$a brave pet owner$t$, $t$a caring person$t$, $t$a diligent student$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- G6A: Yawning (level 6, any round; 130 words)
  -- Key: booklet key has 7 letters for 8 questions; the manual's key is kept.
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 6 and title = $t$Yawning$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', null, $t$A$t$, 6, $t$Yawning$t$,
            $t$Have you ever yawned? When do you do so?
In this selection, let's find out why we yawn.$t$,
            $t$What makes us yawn? Yawning is something that we cannot control. Even in the mother's womb, eleven-week-old babies have been observed to yawn. But why do we do it? One popular explanation for yawning is that a person may be tired or bored. Although many believe this to be true, it cannot explain why athletes yawn before an event or why dogs yawn before an attack.
It is said that yawning is caused by a lack of oxygen and excess carbon dioxide. A good example of this is when we yawn in groups. We yawn because we are competing for air.
Others even believe that we yawn to cool our brains off. Cool brains allow us to think more clearly so yawning is said to help us become more alert.$t$,
            130)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$What is a fact about yawning?$t$,
          jsonb_build_array($t$It is something we cannot control.$t$, $t$It is something only humans do$t$, $t$It is a result of boredom.$t$, $t$It happens after birth.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$Which of the following might make us yawn?$t$,
          jsonb_build_array($t$reading a book$t$, $t$being in a crowded room$t$, $t$being around plants$t$, $t$being in a small air-conditioned car$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  -- CHECK: Q3 asks for the meaning of "involuntary", a word the passage does not use. Kept as printed.
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$What does the word "involuntary" mean?$t$,
          jsonb_build_array($t$expected$t$, $t$unexpected$t$, $t$within control$t$, $t$uncontrollable$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Which of the following may be a benefit of yawning?$t$,
          jsonb_build_array($t$It warns us of possible attacks by dogs.$t$, $t$It provides us the carbon dioxide we need.$t$, $t$It cools our brains.$t$, $t$It balances the amount of oxygen and carbon dioxide.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$According to the selection, what is most likely to happen after we yawn?$t$,
          jsonb_build_array($t$We will become more alert.$t$, $t$We will be less tired.$t$, $t$We will be less sleepy.$t$, $t$We will be calmer.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$In the selection, how is the word 'compete' used in the phrase "competing for air?"$t$,
          jsonb_build_array($t$struggling to take in some air$t$, $t$arguing about breathing$t$, $t$battling it out for oxygen$t$, $t$racing to breathe more air$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$Which of the following shows evidence that "yawning" is "competing for air?"$t$,
          jsonb_build_array($t$The passengers in an elevator yawned.$t$, $t$Several people yawned while picnicking at an open field.$t$, $t$Two people yawned inside a room with air-conditioning.$t$, $t$Three students yawned in a big empty room.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$Which of the following is the best response when we see a person/animal yawn?$t$,
          jsonb_build_array($t$Have the person eat a food item that is a good source of energy.$t$, $t$Change the topic of conversation to a more interesting one.$t$, $t$Turn on an electric fan or source of ventilation.$t$, $t$Run away to avoid being attacked.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- G6B: Laughter (level 6, any round; 142 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 6 and title = $t$Laughter$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', null, $t$B$t$, 6, $t$Laughter$t$,
            $t$What happens when you laugh?
In the selection, let's find out what happens when one laughs.$t$,
            $t$People love to laugh. We love it so much when there are jokes, jobs, and shows that are made to make us laugh. Even though laughing seems natural, not many species are able to do so.
Laughing involves the performance of rhythmic, involuntary movements, and the production of sounds. We are able to laugh using fifteen facial muscles, our respiratory system, and sometimes even our tear ducts.
We are lucky that we are able to laugh because there is strong evidence that laughter can help improve health. Laughter boosts the immune system and adds another layer of protection from disease. Since laughter also increases blood flow, it improves the function of blood vessels that helps protect the heart. Laughter also relaxes the whole body by relieving tension and stress. Finally, laughter also brings out the body's natural feel-good chemicals that promote well-being.$t$,
            142)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$What is laughing?$t$,
          jsonb_build_array($t$It is the voluntary reception of sounds.$t$, $t$It is the voluntary production of sounds.$t$, $t$It is the involuntary production of sounds.$t$, $t$It is the voluntary use of our facial muscles.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What does the statement, "There are jokes, jobs, and shows that are made to make us laugh," imply in this selection?$t$,
          jsonb_build_array($t$Laughter is something we have to work at.$t$, $t$Comedy shows are good sources of income.$t$, $t$Laughter is an important part of our life.$t$, $t$Jokes and comedy shows are expensive ways to make us laugh.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$In what way does laughing prevent us from getting sick?$t$,
          jsonb_build_array($t$It lets us have full use of our respiratory system.$t$, $t$It helps boost our immune system.$t$, $t$It allows us to use our tear ducts.$t$, $t$It exercises our facial muscles.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$If laughter increases blood flow, which body system does it help?$t$,
          jsonb_build_array($t$nervous system$t$, $t$respiratory system$t$, $t$excretory system$t$, $t$circulatory system$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Which word CANNOT be used to describe laughing?$t$,
          jsonb_build_array($t$rhythmic$t$, $t$voluntary$t$, $t$uncontrollable$t$, $t$functional$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Which of the following facts about laughter would be helpful to a hardworking secretary at a busy office?$t$,
          jsonb_build_array($t$Laughter uses fifteen facial muscles.$t$, $t$Laughter keeps tension and stress away.$t$, $t$Laughter may help protect us from diseases.$t$, $t$Laughter brings out the 'feel good' chemicals.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$Which of the following is the best title for the selection?$t$,
          jsonb_build_array($t$Laughter is the answer.$t$, $t$Laughter is the best medicine.$t$, $t$Laughter is what sets humans apart.$t$, $t$Laughter affects the human condition.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$Which of the following would be the most ideal place to spread the good effects of laughter?$t$,
          jsonb_build_array($t$sari-sari store$t$, $t$gas station$t$, $t$hospital$t$, $t$market$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- G6C: Effects of Anger (level 6, any round; 162 words)
  -- Key: booklet differs from the manual at Q8 b->c (manual -> booklet).
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 6 and title = $t$Effects of Anger$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', null, $t$C$t$, 6, $t$Effects of Anger$t$,
            $t$What happens to your body when you are angry?
In this selection, let's find out what happens to our body when we are angry.$t$,
            $t$Anger is often viewed as harmful. It does not only affect the person feeling this anger but those around him or her. As these feelings get stronger, changes occur in our body. Our faces turn red and carry a frown. Our teeth are clenched and our hands are closed tight. Our breathing becomes heavy and this makes our heart beat faster. Our shoulder and neck muscles become stiff and our blood pressure begins to rise. All these things happen because our body is preparing for something. It is preparing for action. However, this action does not have to be harmful.
People are often guilty about feeling angry. But, anger can be viewed positively. Feelings of anger tell you that something is not right and that something needs to change. The challenge lies in making sure that actions resulting from anger will help rather than harm. Expressing our feelings can help others understand the source of our anger rather than fear its consequences.$t$,
            162)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Which is NOT an observed change in our body when we get angry?$t$,
          jsonb_build_array($t$Our face turns red.$t$, $t$Our heart beats faster.$t$, $t$Our shoulders become stiff.$t$, $t$Our breathing becomes slow.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$In the sentence, "Changes occur in our body," which of the following words is a synonym for the word occur?$t$,
          jsonb_build_array($t$stay$t$, $t$form$t$, $t$happen$t$, $t$transform$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Why do people sometimes feel guilty for being angry?$t$,
          jsonb_build_array($t$Anger may hurt others.$t$, $t$Anger is not a feeling you should show to other people.$t$, $t$Anger may cause us to create positive change in the world.$t$, $t$Anger may cause us to be motivated to act on something.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Which of these actions is based on anger as a positive form of expression?$t$,
          jsonb_build_array($t$focusing on what is wrong$t$, $t$saying hurtful words$t$, $t$identifying the root of the problem$t$, $t$keeping our emotions bottled up inside of us$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Which of these actions are based on anger as a form of motivation?$t$,
          jsonb_build_array($t$asking the person we are angry at to think of how the problem can be resolved$t$, $t$giving the person that we are angry at the silent treatment$t$, $t$kicking a chair aside and screaming out loud$t$, $t$seeking the help of a third person to side with you$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$What is one benefit of feeling angry?$t$,
          jsonb_build_array($t$It provides a form of exercise for our heart and blood vessels.$t$, $t$It prepares us for future occasions that we might feel angry.$t$, $t$It serves as a signal that something is not right.$t$, $t$It changes how our mind works.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$In the selection, what is the meaning of the word "challenge?"$t$,
          jsonb_build_array($t$It refers to a task that is new.$t$, $t$It refers to a task that is different$t$, $t$It refers to a task that is assigned to us.$t$, $t$It refers to a task that is difficult to do.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$In the selection, which trait would be most helpful when trying to use our anger in a positive way?$t$,
          jsonb_build_array($t$being obedient$t$, $t$being honest$t$, $t$being thoughtful$t$, $t$being hardworking$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- G6D: Dreams (level 6, any round; 141 words)
  -- Key: booklet differs from the manual at Q2 d->a (manual -> booklet).
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 6 and title = $t$Dreams$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', null, $t$D$t$, 6, $t$Dreams$t$,
            $t$Have you ever had a dream?
Why do we dream?$t$,
            $t$We often say "Sweet dreams," but have you ever wondered why we dream? Some say that dreaming is our brain's way of exercising. While we sleep, our brain may be testing the connections and pathways to see if they are working well. Others believe that dreaming is our brain's way of sorting out problems. Problems that have not been addressed during the day are sometimes resolved in our sleep. Yet another explanation is that dreaming is our brain's way of fixing and organizing all the information we have. While sleeping, our brains have a chance to sort out the information that we want to keep from the stuff we no longer want. Still another idea is that dreams are just another form of thinking. Will we ever get to know the answer to this question? Maybe we should sleep on it.$t$,
            141)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Based on the selection, what does our brain exercise through sleeping?$t$,
          jsonb_build_array($t$the connections and pathways$t$, $t$the left and right hemispheres$t$, $t$the content and concepts$t$, $t$the gray matter$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$Which of the statements does NOT show how dreams fix our problems?$t$,
          jsonb_build_array($t$As we dream, we constantly think about what we have learned or experienced.$t$, $t$Our dreams help us focus on things we are unable to notice during the day.$t$, $t$Our brain comes up with solutions in our sleep.$t$, $t$Our brain sorts and files information.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$How does a brain - through dreams - perform the function of an office clerk?$t$,
          jsonb_build_array($t$It sorts information we need from what we don't need.$t$, $t$It files what we know into fixed categories.$t$, $t$It clears the board to store new information.$t$, $t$It functions alone.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Based on how it is used in the selection, which of the following words is a synonym for the word "resolved?"$t$,
          jsonb_build_array($t$accommodated$t$, $t$reflected$t$, $t$decided$t$, $t$fixed$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Which of the following statements is NOT true about the brain?$t$,
          jsonb_build_array($t$Our brain makes connections.$t$, $t$Our brain never stops thinking.$t$, $t$Sleeping is our brain's way of shutting down.$t$, $t$Our brain replays our experiences as we sleep.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Which question is the selection trying to answer?$t$,
          jsonb_build_array($t$What are the types of dreams?$t$, $t$Why are our reasons for dreaming?$t$, $t$Are all dreams sweet?$t$, $t$How can we stop from dreaming?$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$In the selection, what does it mean to "sleep on it"?$t$,
          jsonb_build_array($t$ignore it$t$, $t$take a nap$t$, $t$think about it$t$, $t$forget about it$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$Which could be a good title for this selection?$t$,
          jsonb_build_array($t$Dreaming: Explained$t$, $t$Preventing Our Dreams$t$, $t$Interpreting One's Dream$t$, $t$Finding Solutions to Dreaming$t$), 'a')
  on conflict (passage_id, question_no) do nothing;

  -- G7Pre: Lili the Lizard and Koko the Gecko (level 7, pre; 357 words)
  -- Key: booklet differs from the manual at Q7 a->c (manual -> booklet).
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 7 and title = $t$Lili the Lizard and Koko the Gecko$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', null, 7, $t$Lili the Lizard and Koko the Gecko$t$,
            null,
            $t$In a land across the green field, far away from the barracks of the Spanish soldiers, there lived a young couple who owned a gecko. His name was Koko whose vibrant color and smooth scales made him the most adorable pet in the house. His well-decorated cage and abundant food proved that he was well taken care of.
In one corner of the house was Lili the lizard who was silently waiting for a chance to eat. While Koko devoured the sumptuous food in his cage, Lili silently worked hard to make both ends meet.
Though they lived in the same house, one was clearly above the other. A wall of discrimination and unequal opportunity was indestructible.
Every day, Koko the gecko's state of living reminded Lili the lizard of the life she wished she could have. A life of great comfort and abundance. However, no matter how Lili wished to be in the state of life where Koko was, a strange feeling told her that something was wrong.
One day, as soon as the sun smiled over the green horizon, Koko the gecko was seen being taken out of the cage. It may be another lucky day for him or otherwise. However, Lili the lizard was on her usual daily routine. Nothing new, nothing special.
When darkness started to clothe the town, the silence that came with it filled the entire house as well. No sound of a gecko was heard. No vibrant color was seen. Only an empty cage.
The couple seemed to be in a happy disposition while looking at a large amount of money on the table near the cage. Lili the lizard watched the entire situation and couldn't help but wonder. "Is it the price that Koko has to pay?" she asked herself.
The following day, when a new gecko was seen in the cage, everything made sense to Lili the lizard and she learned one lesson she will never forget.
"One may be living in comfort inside a cage but nothing is more comforting than having the freedom you deserve. Freedom from bondage and suppression." Lili the lizard told her children.$t$,
            357)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Which of the following best describes the time setting of the story?$t$,
          jsonb_build_array($t$The story took place after the Spaniards left the Philippines.$t$, $t$The story took place before the Spaniards came to the Philippines.$t$, $t$The story took place when the Spaniards fought the Americans.$t$, $t$The story took place while the Spaniards were in the Philippines.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$In paragraph 2, what does the word "devoured" mean?$t$,
          jsonb_build_array($t$boasted about the food$t$, $t$divided the food$t$, $t$ate up the food$t$, $t$fought over the food$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$What is the conflict in the story?$t$,
          jsonb_build_array($t$Gecko was in a cage.$t$, $t$Lili was envious of Gecko.$t$, $t$Lili was not beautiful.$t$, $t$The couple was poor.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$What does the green horizon in Paragraph 5 refer to?$t$,
          jsonb_build_array($t$desert$t$, $t$farm$t$, $t$lake$t$, $t$sea$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Which paragraph shows the difference in the life between Lili and Gecko?$t$,
          jsonb_build_array($t$Paragraph 2$t$, $t$Paragraph 5$t$, $t$Paragraph 7$t$, $t$Paragraph 9$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$What time of the day is indicated in this line "the sun smiled over the green horizon" in paragraph 5?$t$,
          jsonb_build_array($t$Dawn$t$, $t$Morning$t$, $t$Night$t$, $t$Noon$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$In paragraph 2, what does the idiomatic expression "make both ends meet" mean?$t$,
          jsonb_build_array($t$to spend according to one's budget$t$, $t$to spend according to one's limit$t$, $t$to spend according to one's needs$t$, $t$to spend according to one's wants$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$Which of the following is an example of a figure of speech?$t$,
          jsonb_build_array($t$A wall of discrimination was indestructible.$t$, $t$He lived a life of great comfort and abundance.$t$, $t$His vibrant color made him the most adorable pet.$t$, $t$The sun smiled over the green horizon.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 9, null, $t$Which are themes explored in the selection?$t$,
          jsonb_build_array($t$Beauty, freedom, happiness$t$, $t$Corruption, equality, contentment$t$, $t$Equality, freedom, contentment$t$, $t$Poverty, equality, happiness$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 10, null, $t$Which type of text is similar to the selection?$t$,
          jsonb_build_array($t$Fable, because it highlights the lesson.$t$, $t$Fairy tale, because it has a happy ending.$t$, $t$Legend, because it tells the origin of something.$t$, $t$Tall tale, because the story is exaggerated.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;

  -- G7A1: Dark Chocolate (level 7, mosy; 152 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 7 and title = $t$Dark Chocolate$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'mosy', $t$A1$t$, 7, $t$Dark Chocolate$t$,
            $t$What is the effect of eating dark chocolates?
In this selection, let's find out the benefits of eating dark chocolate.$t$,
            $t$Dark chocolate finds its way into the best ice creams, biscuits and cakes. Although eating chocolate usually comes with a warning that it is fattening, it is also believed by some to have magical and medicinal effects. In fact, cacao trees are sometimes called Theobroma cacao which means "food of the gods."
Dark chocolate has been found out to be helpful in small quantities. One of its benefits is that it has some of the most important minerals and vitamins that people need. It has antioxidants that help protect the heart. Another important benefit is that the fat content of chocolate does not raise the level of cholesterol in the blood stream. A third benefit is that it helps address respiratory problems. Also, it has been found out to help ease coughs and respiratory concerns. Finally, chocolate increases serotonin levels in the brain. This is what gives us a feeling of well-being.$t$,
            152)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Why was chocolate called Theobroma cacao?
It is considered to be _____.$t$,
          jsonb_build_array($t$fattening food$t$, $t$magical tree$t$, $t$medicinal candy$t$, $t$food of the gods$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$Which statement is true?$t$,
          jsonb_build_array($t$All chocolates have medicinal properties.$t$, $t$In small doses, dark chocolate is fattening.$t$, $t$Dark chocolate has minerals and vitamins.$t$, $t$Chocolate raises the level of cholesterol.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$What is found in dark chocolate that will help encourage its consumption?$t$,
          jsonb_build_array($t$antioxidants$t$, $t$sugar$t$, $t$fats$t$, $t$milk$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$After we eat chocolate, which of these is responsible for making us feel good?$t$,
          jsonb_build_array($t$cacao$t$, $t$theobroma$t$, $t$serotonin$t$, $t$antioxidants$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$If a person coughs and is asked to have some chocolate, why would this be good advice?$t$,
          jsonb_build_array($t$Dark chocolate helps respiratory problems.$t$, $t$Dark chocolate helps circulation.$t$, $t$Dark chocolate does not raise the level of cholesterol.$t$, $t$Dark chocolate has vitamins and minerals.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Which of the following body systems does not directly benefit from the consumption of dark chocolate?$t$,
          jsonb_build_array($t$Circulatory system$t$, $t$Respiratory system$t$, $t$Excretory system$t$, $t$Nervous system$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$Which important fact shows that dark chocolate may be safe for the heart?$t$,
          jsonb_build_array($t$It may ease coughs.$t$, $t$It helps address respiratory problems.$t$, $t$It does not raise the level of cholesterol.$t$, $t$In small quantities, dark chocolate has been said to be medicinal.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$What does "address" mean in the second paragraph?$t$,
          jsonb_build_array($t$to locate$t$, $t$to identify$t$, $t$to deal with$t$, $t$to recognize$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- G7A2: Diving (level 7, mosy; 163 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 7 and title = $t$Diving$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'mosy', $t$A2$t$, 7, $t$Diving$t$,
            $t$Some people explore the sea through diving. But they should be able to breathe. How do the divers breathe underwater?
In the passage that you are going to read, find out: how divers breathe underwater.$t$,
            $t$Humans do not have the capacity to breathe underwater unaided by external devices. A diver who wants to stay underwater for more than a few minutes must breathe air on a special mixture of gases. He can wear diving suits and have air pumped to him from above or he can carry tanks of air on his back and breathe through a hose and a mouthpiece.
Early divers discovered that it is not enough to supply air to breathe comfortably underwater. The diver's body is under great pressure in deep water because water weighs 800 times as much as air. Tons of water push against the diver deep in the sea. When this happens, his blood takes in some of the gases he breathes.
When the diver rises to the surface, the water pressure becomes less. If he rises too quickly, the gases in his blood form bubbles that make breathing difficult. He suffers from bends, causing him to double up in pain.$t$,
            163)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$What is the purpose of the diving suit?$t$,
          jsonb_build_array($t$to track the diver's location$t$, $t$to make the diver stay afloat$t$, $t$to dive to the bottom of the sea faster$t$, $t$to pump air from the surface of the sea$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$The hose and the mouthpiece of the diver are used _______________.$t$,
          jsonb_build_array($t$for breathing$t$, $t$for finding direction$t$, $t$for lighting the way$t$, $t$for communicating$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$The second paragraph informs the reader that ___________________.$t$,
          jsonb_build_array($t$water is heavier than air$t$, $t$it is easy to float on the water$t$, $t$it is exciting to stay under water$t$, $t$it is difficult to breathe while diving$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$It is easy for swimmers to float in the water's surface because ______________________.$t$,
          jsonb_build_array($t$they can see where they are heading for$t$, $t$there is lesser water pressure$t$, $t$there is more air to breathe$t$, $t$there is minimal danger$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$From the phrase 'a diver suffers from bends,' the reader can guess that a bend is ____________________________.$t$,
          jsonb_build_array($t$a reverse turn$t$, $t$an intense pain$t$, $t$a wrong direction$t$, $t$an incorrect information$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$To avoid pain when rising to the surface, a diving instructor should tell a swimmer to _______________________________.$t$,
          jsonb_build_array($t$"go up as fast as you can"$t$, $t$"swim to the surface slowly"$t$, $t$"avoid bringing things from undersea.$t$, $t$"inspect your hose and mouthpiece first"$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$Which statement is true in the selection?
Water pressure ___________________________________.$t$,
          jsonb_build_array($t$is heavier on the sea surface$t$, $t$is greater in the deep part of the sea$t$, $t$feels more while one is going up the surface$t$, $t$is the same on the surface and in the deep part of the sea$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$Who among the following readers will benefit most from this selection?$t$,
          jsonb_build_array($t$the sea divers$t$, $t$the coast guards$t$, $t$the sea travelers$t$, $t$the swimming instructors$t$), 'a')
  on conflict (passage_id, question_no) do nothing;

  -- G7B1: Sneezing (level 7, mosy; 152 words)
  -- Key: booklet key is missing a letter (the rest shifted); the manual's key is kept.
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 7 and title = $t$Sneezing$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'mosy', $t$B1$t$, 7, $t$Sneezing$t$,
            $t$When do you usually sneeze?
In the selection, let's find out what makes one sneeze.$t$,
            $t$Sneezing happens when our body is trying to remove an irritation found inside the nose. A special name for this process is sternutation.
How does a sneeze happen? When your nose is tickled, the sneeze center in our brain receives a message. Soon, the other parts of the body that work together to create a sneeze such as the abdominal muscles, chest muscles, the diaphragm, the muscles of the vocal chords, the back of the throat, and the eyelids receive this message. An explosion as fast as 161 kilometers per hour sends the irritant speeding out of your nose. Examples of irritants in the air are dust, pepper, or allergens such as pollen. Some experience having a photic reflex and sneeze as soon as they are under the bright sun. Now, if it ever happens that a sneeze of yours gets stuck, look towards a bright light to unstick your stuck sneeze.$t$,
            152)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$What is sternutation?$t$,
          jsonb_build_array($t$the voluntary process of expelling dirt and dust from inside our nose$t$, $t$the involuntary process of removing an irritation inside the nose$t$, $t$a person's natural reaction to bright light$t$, $t$an explosion of allergens$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$Sneezing happens ____________________________.$t$,
          jsonb_build_array($t$to release energy$t$, $t$to expel an irritant$t$, $t$to remove nose hair$t$, $t$in response to a cough$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Which of the following is NOT an example of an allergic reaction?$t$,
          jsonb_build_array($t$sneezing in a dusty room$t$, $t$pepper-induced sternutation$t$, $t$photic reflex from sun exposure$t$, $t$Sneezing when exposed to pollen$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Which of the following does NOT help to create a sneeze?$t$,
          jsonb_build_array($t$abdominal muscles$t$, $t$chest muscles$t$, $t$nasal passages$t$, $t$voice box$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Which is the best advice to follow to unstick a sneeze?$t$,
          jsonb_build_array($t$look towards a bright light$t$, $t$tickle our nostrils$t$, $t$blow one's nose$t$, $t$cough out loud$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Why must we cover our nose when we sneeze?$t$,
          jsonb_build_array($t$to prevent the further intake of pepper powder$t$, $t$to prevent the allergens from multiplying$t$, $t$to prevent irritants from spreading$t$, $t$to prevent ourselves from sneezing$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$Which of the following is the best thing to do if you feel a sneeze coming along?$t$,
          jsonb_build_array($t$Take cold medicine.$t$, $t$Have a body check-up.$t$, $t$Move away from others.$t$, $t$Open a window that faces a garden.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$The main idea of this selection is$t$,
          jsonb_build_array($t$the different kinds of sneeze$t$, $t$how sneezing happens$t$, $t$the cure for sneezing$t$, $t$the origin of sneezing$t$), 'b')
  on conflict (passage_id, question_no) do nothing;

  -- G7B2: The Brain (level 7, mosy; 160 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 7 and title = $t$The Brain$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'mosy', $t$B2$t$, 7, $t$The Brain$t$,
            $t$When we are asked difficult questions, we are told "Use your brain." What do you know about the functions of the brain?
Compare your answer with what the selection says.$t$,
            $t$The brain is the center of the nervous system. It interprets stimuli and tells the body how to react.
The brain has three major parts. The part that controls balance, coordination and muscle movement is called the cerebellum. It makes sure that the muscles work well together. For example, a gymnast is able to balance on a beam because of the cerebellum.
The medulla is a long stem that connects the brain to the spinal cord. It tells one's body to do things without thinking about them. Digesting food or breathing even while asleep are examples of these involuntary actions.
On the other hand, there are actions that one decides to do. It is the largest part of the brain— the cerebrum— that is responsible for these voluntary movements. Without it, one will not be able to kick a ball or dance at all.
The brain might seem small but it is so powerful as it controls one's entire body.$t$,
            160)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Which is the best description of the brain?$t$,
          jsonb_build_array($t$It makes people intelligent.$t$, $t$It keeps one's body healthy.$t$, $t$It helps everyone think well.$t$, $t$It dictates how the body will react to stimuli.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$In the sentence, "The brain interprets stimuli," the meaning of interpret is __________.$t$,
          jsonb_build_array($t$assign roles$t$, $t$recall facts$t$, $t$discuss ideas$t$, $t$make sense of$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$What will the brain likely tell you if you happen to hold on to something hot?$t$,
          jsonb_build_array($t$"I wonder how hot it is."$t$, $t$"Don't drop it!"$t$, $t$"Hold tight!"$t$, $t$"Let go!"$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Which is an example of involuntary action?$t$,
          jsonb_build_array($t$circulating blood all over the body$t$, $t$punching one's classmate$t$, $t$clapping your hands$t$, $t$tickling your friend$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Which part of the brain connects to the spinal cord?$t$,
          jsonb_build_array($t$the nerves$t$, $t$the medulla$t$, $t$the cerebrum$t$, $t$the cerebellum$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$What is the function of the cerebellum?$t$,
          jsonb_build_array($t$It sends messages to the cerebrum.$t$, $t$It connects the medulla to the cerebrum.$t$, $t$It controls balance and muscle movements.$t$, $t$It tells the parts of the body how they should function.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$When you want someone to think of the right answer, you might say,$t$,
          jsonb_build_array($t$"Use your senses."$t$, $t$"Sharpen your cerebrum."$t$, $t$"Give your medulla a job."$t$, $t$"Let your cerebellum function."$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$What is the main idea of the selection?$t$,
          jsonb_build_array($t$The brain controls the senses.$t$, $t$The brain interprets all actions.$t$, $t$The brain has three main parts.$t$, $t$The brain controls one's entire body$t$), 'd')
  on conflict (passage_id, question_no) do nothing;

  -- G7C1: Dust (level 7, mosy; 185 words)
  -- Key: booklet differs from the manual at Q2 d->b, Q7 a->c (manual -> booklet).
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 7 and title = $t$Dust$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'mosy', $t$C1$t$, 7, $t$Dust$t$,
            $t$Do you have dust at home?
In the story, let's find out what dust is made of$t$,
            $t$No matter how often we sweep the floor of our homes, we are still able to gather together a considerable amount of dust. Dust is all around us. It gathers on bookshelves, on furniture— old or new. These particles rest on any still object— undisturbed until touched or wiped clean.
Dust, which was first believed to be made of dead skin has been found to be a mix of different things. Some of the common ingredients of dust particles include animal fur, dead insects, food, fiber from clothes, beddings, soil and other chemicals. Although most of household dust comes from the outside through doors, windows and shoes, other dust particles come from within. Scientists have discovered that the mix of dust from each household actually depends on four things: the climate, the age of the house, the number of persons who live in it and their individual cooking, cleaning and smoking habits.
Making our homes free of dust may not be possible but lessening the amount of dust that we keep in our homes will help avoid possible allergies and allow us to breathe well.$t$,
            185)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Which of the following is NOT true about dust?$t$,
          jsonb_build_array($t$Dust causes allergies.$t$, $t$Dust is made of dead skin only.$t$, $t$Dust comes from both within the home and outside of it.$t$, $t$The amount of dust in the house may depend on the climate.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$Knowing the contents of the dust in our homes will determine ________.$t$,
          jsonb_build_array($t$how dust can be cleaned up$t$, $t$where the dust is coming from$t$, $t$what one might add to one's home$t$, $t$the lifestyle of the occupants$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Among the sources of dust, which is NOT within one's control?$t$,
          jsonb_build_array($t$the personal habits of family members$t$, $t$the number of persons in the home$t$, $t$the age of the house$t$, $t$the climate$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$What is the greatest risk that one faces in having a dusty house? A dusty house might ________.$t$,
          jsonb_build_array($t$cause the incidence of allergies$t$, $t$be a reason for accidents in the house$t$, $t$increase the temperature of the environment$t$, $t$result in the early destruction of the furniture$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Knowing the composition of dust will especially help persons with ______.$t$,
          jsonb_build_array($t$motor difficulties$t$, $t$physical disabilities$t$, $t$circulatory concerns$t$, $t$respiratory problems$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$In this selection, the word "habits" refers to ________.$t$,
          jsonb_build_array($t$one's unusual behavior$t$, $t$being addicted to something$t$, $t$the work one occasionally performs$t$, $t$the manner by which one repeatedly does a task$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$How did the writer develop this selection about dust?$t$,
          jsonb_build_array($t$by giving examples$t$, $t$by narrating some events$t$, $t$by stating the cause and effect$t$, $t$by identifying the problem and the solutions$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$Which is an appropriate title of this selection?$t$,
          jsonb_build_array($t$Keeping the Houses Dust-Free$t$, $t$Sources of Dust in Our Homes$t$, $t$Effects of Dusty Homes$t$, $t$Diseases Due to Dust$t$), 'b')
  on conflict (passage_id, question_no) do nothing;

  -- G7C2: Air Currents (level 7, mosy; 153 words)
  -- Key: booklet differs from the manual at Q3 b->c, Q7 b->a (manual -> booklet).
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 7 and title = $t$Air Currents$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'mosy', $t$C2$t$, 7, $t$Air Currents$t$,
            $t$When do you experience rain in the Philippines
In the selection, find out which parts of the country experience rain during certain months of the year$t$,
            $t$Wind is the natural movement of the air from one place to another. It affects the climate of a place. There are three major air streams that greatly affect our climate.
From November to February, mornings are colder because of the northeast monsoon wind. It blows from Siberia which is a very frigid place. It brings along temperature and rain that make us shiver.
The wind from June to October, is warm and humid. During this time, the western section of our country experiences strong rains brought about by the southwest monsoon wind blowing from Australia.
From March to early May, trade winds coming from the east or northeast reach the Philippines. It brings rains to the eastern part of our country. Trade winds are warm and moist and bring hot temperature with little rain.
Isn't it amazing that each one of these air streams brings some amount of rain to the Philippines?$t$,
            153)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$The northeast monsoon wind blowing from Siberia causes _________.$t$,
          jsonb_build_array($t$heavy rains$t$, $t$windy days$t$, $t$hot temperature$t$, $t$cold temperature$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$Which of the following statements is true about the wind?$t$,
          jsonb_build_array($t$The wind attracts tourists to visit a place.$t$, $t$The wind affects the climate of a place.$t$, $t$The wind always comes from one direction.$t$, $t$The wind moves at select times of the year.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Siberia is a very frigid place. What is an antonym for the word frigid?$t$,
          jsonb_build_array($t$very moist$t$, $t$very cold$t$, $t$very hot$t$, $t$very windy$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$You are going on a vacation at your cousin's province in the eastern part of the country in March. What type of clothes should you bring?$t$,
          jsonb_build_array($t$new$t$, $t$thin$t$, $t$thick$t$, $t$modern$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Among these different air streams in the Philippines, which is the most appropriate for wearing very heavy clothes?$t$,
          jsonb_build_array($t$trade winds$t$, $t$easterly winds$t$, $t$southeast monsoons$t$, $t$northeast monsoons$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Which among these statements is backed up by the selection?$t$,
          jsonb_build_array($t$Northeast monsoons account for strong rains during the June opening of classes.$t$, $t$Southwest monsoons bring some amount of rain to the country even in May.$t$, $t$Eastern portions of the country experience strong rains from June to October.$t$, $t$Western portions of the country experience strong rains from June to October.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$What device did the author use to develop the selection?$t$,
          jsonb_build_array($t$examples$t$, $t$cause and effect$t$, $t$a series of events$t$, $t$problem and solution$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$Which could be another title of the selection?$t$,
          jsonb_build_array($t$Different Causes of Heavy Rains$t$, $t$How Air Streams Affect Climate$t$, $t$Northwest and Southwest Monsoons$t$, $t$Hot and Cold Temperature in the Country$t$), 'b')
  on conflict (passage_id, question_no) do nothing;

  -- G7D1: Pain (level 7, mosy; 164 words)
  -- Key: booklet differs from the manual at Q4 b->c (manual -> booklet).
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 7 and title = $t$Pain$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'mosy', $t$D1$t$, 7, $t$Pain$t$,
            $t$Have you ever felt pain?
In this selection, let's find out how the body senses pain.$t$,
            $t$How do we sense pain? The human body has nociceptors to receive an electrical impulse that is sent to part of the brain that recognizes pain. Memories of these sensations are formed to help us avoid painful objects and experiences and prevents us from repeating past mistakes that may have hurt us in some way. But pain is more complex. It is not only a physical experience but an emotional and psychological one as well. When all of these come together, it is called suffering.
The mind is not alone in recognizing pain. The nervous system is also able to store such information. Even when a person loses a finger or a limb, the pain that was once felt may become a chronic one— one that keeps recurring. The best way to avoid this is to prevent pain memories from forming. The use of anesthesia prevents the mind from creating these memories. Drugs that prevent pain such as analgesics help lessen the pain sensed.$t$,
            164)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$What are "nociceptors?"$t$,
          jsonb_build_array($t$electrical impulses$t$, $t$memories of pain$t$, $t$nerve receptors$t$, $t$sensations of pain$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$How do memories of pain help us?$t$,
          jsonb_build_array($t$These constantly remind us of what hurts.$t$, $t$These help dull the senses.$t$, $t$These help us re-experience the pain.$t$, $t$These inform us on what to watch out for.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Suffering is the complex mix of __________________.$t$,
          jsonb_build_array($t$physical, mental and spiritual experiences$t$, $t$physical, psychological and social influences$t$, $t$physical, sociological, and cognitive factors$t$, $t$physical, emotional and psychological experiences$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Which of the following is an example of how memories of pain help us?$t$,
          jsonb_build_array($t$A baby crying at the sight of the needle$t$, $t$Drinking a pain killer once a headache starts$t$, $t$Asking if a dental procedure will hurt$t$, $t$We relive these experiences through our dreams$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Which is an example of helping the body avoid the creation of memories for pain?$t$,
          jsonb_build_array($t$Avoiding the use of anesthesia$t$, $t$Drinking a painkiller once a headache starts$t$, $t$Talking about a painful experience with a friend$t$, $t$Being given an anesthetic before a dental procedure$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$In the selection, how was the word chronic used in the phrase "chronic pain"?$t$,
          jsonb_build_array($t$continuous$t$, $t$in-born$t$, $t$throbbing$t$, $t$worsening$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$Which of the following adjectives best describes our memories' role in managing pain?$t$,
          jsonb_build_array($t$curative$t$, $t$corrective$t$, $t$preventive$t$, $t$restorative$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$In the selection, what does it mean to 'sense pain'?$t$,
          jsonb_build_array($t$create pain$t$, $t$recognize pain$t$, $t$remember pain$t$, $t$understand pain$t$), 'b')
  on conflict (passage_id, question_no) do nothing;

  -- G7D2: Ecosystems (level 7, mosy; 160 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 7 and title = $t$Ecosystems$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'mosy', $t$D2$t$, 7, $t$Ecosystems$t$,
            $t$How would you react if there is a stranger in your house?
In this selection, find out how organisms react if a new organism came to their homes.$t$,
            $t$Ecosystems consist of living and non-living organisms in an area. These include plants, animals, microbes, and elements like soil, water, and air. The living organisms depend on both living and non-living aspects of an ecosystem.
An ecosystem can be as small as a puddle or as big as an ocean. It is a very delicate balance, with these life forms sustaining one another. Disruptions to an ecosystem may prove disastrous to all its organisms.
When a new plant or animal is suddenly placed in an ecosystem, it will surely compete with the original inhabitants for resources. This stranger may even push out the natural organisms, causing them to be extinct. The organisms that depended on the extinct organisms will definitely be affected.
The balance in ecosystems have been unsettled by natural disasters such as fires, floods, storms, and volcanic eruptions. However, in recent years and ironically, in the name of progress, human activity has affected many ecosystems around the world.$t$,
            160)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Which among the following is NOT a good description for an ecosystem?$t$,
          jsonb_build_array($t$animals and plants relying on each other to survive$t$, $t$a place where people are friendly to the environment$t$, $t$a biological community where organisms affect each other$t$, $t$a variety of living and non-living things in a particular area$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$Why is an ecosystem considered to be a delicate balance?$t$,
          jsonb_build_array($t$There are big ecosystems and small ecosystems that have to be balanced.$t$, $t$Not all ecosystems weigh the same so their weight needs to be distributed.$t$, $t$A change in an ecosystem can have tremendous effects on all its organisms.$t$, $t$Different organisms always have equal importance in any given ecosystem.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Which of the following is NOT one of the natural disasters that have caused ecosystems to be unsettled?$t$,
          jsonb_build_array($t$fires$t$, $t$floods$t$, $t$storms$t$, $t$humans$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Based on the selection, which of the following is true about human progress and ecosystems?$t$,
          jsonb_build_array($t$Human progress sometimes causes ecosystems to suffer.$t$, $t$Human activity promotes the development of ecosystems.$t$, $t$Human activity helps find solutions to ecological problems.$t$, $t$Human progress causes different ecosystems to be progressive.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$According to the selection, a new organism introduced in an ecosystem can have an effect on an original inhabitant when _________________.$t$,
          jsonb_build_array($t$it fights with and eventually eats the original inhabitant$t$, $t$it consumes resources intended for the original inhabitant$t$, $t$it makes the original inhabitant feel strange in the ecosystem$t$, $t$it contributes to disasters that upset the balance in the system$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$What should human beings do in order to maintain the balance in different ecosystems?$t$,
          jsonb_build_array($t$Cut down a lot of trees so that there is more space for animals to live in.$t$, $t$Take corals from the sea so that fish would have more freedom to swim.$t$, $t$Plant more trees in order to replace those that have been cut down.$t$, $t$Catch a lot of tuna so that nothing will eat the mackerel or the small fish.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  -- CHECK: Q7 refers to a food-chain diagram that is only in the printed booklet.
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$The diagram below shows an ocean ecosystem. The arrows point to the food source of the succeeding organism. If a new organism is introduced into the system and it eats the shrimplike creatures, how will this indirectly affect the mackerel?$t$,
          jsonb_build_array($t$The mackerel will have no more shrimplike creatures to eat.$t$, $t$The mackerel will still be eaten by the tuna fish as it continues to consume the small fish.$t$, $t$The mackerel will be eaten by the small fish which now has to look for a new food source.$t$, $t$The mackerel might lose its food since without a food source, the small fish could die.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  -- CHECK: Q8 same diagram as Q7.
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$Using the same diagram, which of the following statements is FALSE?$t$,
          jsonb_build_array($t$The small fish depends solely on shrimplike creatures for food.$t$, $t$The tuna fish depends solely on the mackerel as its food source.$t$, $t$The large shark depends solely on the tuna fish as its food source.$t$, $t$The shrimplike creatures depend solely on one-celled life for food.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;

  -- G7Post: The Jeepney: A Filipino Tradition (level 7, post; 289 words)
  -- Key: booklet differs from the manual at Q1 d->c, Q9 a->b (manual -> booklet).
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 7 and title = $t$The Jeepney: A Filipino Tradition$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', null, 7, $t$The Jeepney: A Filipino Tradition$t$,
            null,
            $t$The jeepney is a popular means for people to travel in the Philippines. After World War II, Filipinos changed the old jeeps left by American soldiers into public vehicles. Today, these brightly colored jeepneys ply every street of the Philippines. Its design is a constant reminder of the Filipinos' creativity and resourcefulness.
Not only that it is a sight to behold, these jeepneys have been so useful to the mass of Filipinos ever since its inception as a public vehicle. As a proof, all throughout the Philippines, there are designated routes and numerous locations for passengers to board and disembark.
It's another thing to be inside the jeepneys. Passengers sit facing each other making conversations more enjoyable. Hence, for many Filipinos, riding the jeepneys offers them a time to socialize conveniently with one another especially in cities where traffic is unbearable.
However, the Filipinos' beloved jeepney is in danger of being off the road in the near future. According to the government, they want to make the jeepneys safer and better for the environment. They plan to replace old jeepneys with new ones that use electricity or less fuel. The drivers are worried because they might not have enough money to buy these new vehicles as they are more expensive than the jeepneys.
Even with this threat, the jeepney remains to be an important part of every Filipino's life. Long after the Americans have left the Philippine soil, its practicality and usefulness continues. People use the jeepneys for varied reasons: go around, visit friends and relatives, go to work, and see new places. It is hard to imagine how life can go on for an ordinary Filipino without the jeepneys. The plan to replace them should be thoughtfully considered.$t$,
            289)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Which of the following is implied in the first paragraph?$t$,
          jsonb_build_array($t$One of the things that Filipinos love to do is travelling.$t$, $t$The American soldiers are very generous.$t$, $t$The Filipino version of the jeepney is more creative.$t$, $t$The jeepney is an original product of the Americans.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What does 'disembark' mean in the sentence, "Jeepneys have designated routes and numerous locations for passengers to board and disembark?"$t$,
          jsonb_build_array($t$to book for a vehicle$t$, $t$to get into a vehicle$t$, $t$to get off a vehicle$t$, $t$to wait for a vehicle$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$What can cause traffic to be unbearable?$t$,
          jsonb_build_array($t$when passengers are not facing each other$t$, $t$when there is no one to talk to while travelling$t$, $t$when there is no time to socialize$t$, $t$when vehicles are either slow or not moving$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$According to the selection, why is the jeepney a popular vehicle among the Filipinos?$t$,
          jsonb_build_array($t$because they are brightly colored.$t$, $t$because they are less expensive.$t$, $t$because they can be found everywhere.$t$, $t$because they can sit facing each other.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$What problem may arise from replacing the jeepneys with vehicles that are run by electricity?$t$,
          jsonb_build_array($t$Many drivers will not buy fuel anymore.$t$, $t$Many jeepney drivers will have no jobs.$t$, $t$More electricity will be consumed.$t$, $t$There will be lesser public vehicles.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Why is the jeepney called a tradition?$t$,
          jsonb_build_array($t$Because people have been riding jeepneys for a very long time$t$, $t$Because jeepneys show the Filipinos' creativity and resourcefulness$t$, $t$Because jeepneys can be seen all over the Philippines$t$, $t$Because the jeepney has many uses for the people$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$What fact is presented in the selection?$t$,
          jsonb_build_array($t$Filipinos love to socialize while travelling around.$t$, $t$Many Filipinos use public utility vehicles like the jeepneys.$t$, $t$The Filipinos are very creative and resourceful.$t$, $t$The government cares for the safety of the environment.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$Which of the following is based on the observations of the author?$t$,
          jsonb_build_array($t$The Filipinos change the jeeps left by the Americans after the war.$t$, $t$The government wants to make the jeepneys safer and better.$t$, $t$The jeepney is a popular means to travel among Filipinos.$t$, $t$The new vehicles are more expensive than the jeepneys.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 9, null, $t$What is the purpose of the last paragraph?$t$,
          jsonb_build_array($t$to convince people to disagree with the government's plan to replace the jeepneys$t$, $t$to emphasize the important role of jeepneys in the lives of the Filipinos$t$, $t$to enumerate the reasons why people consider jeepneys useful$t$, $t$to inform people about what happened to the jeeps left by the Americans$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 10, null, $t$Which of the following best presents a summary of the selection?$t$,
          jsonb_build_array($t$Americans gave the Filipinos their jeeps so that we can use them as vehicles.$t$, $t$Filipinos love the jeepneys because it is a safe way to travel around.$t$, $t$The government will phase out the jeepneys because they are not safe.$t$, $t$The jeepney, a popular vehicle in the Philippines is in danger of being phased out.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;

  -- G8Pre: The Amazing World of Coral Reefs (level 8, pre; 303 words)
  -- Key: booklet differs from the manual at Q1 a->d, Q5 b->a, Q8 b->a (manual -> booklet).
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 8 and title = $t$The Amazing World of Coral Reefs$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', null, 8, $t$The Amazing World of Coral Reefs$t$,
            null,
            $t$Coral reefs are underwater cities teeming with life, vibrant and diverse ecosystems that are vital to the health of our oceans. They are formed by tiny creatures called coral polyps, which build hard, calcium carbonate skeletons that grow together to create massive structures. These structures provide a home for an incredible array of marine life, from colorful fish and graceful sea turtles to tiny invertebrates and even sharks.
The vibrant colors of coral reefs are a result of a symbiotic relationship between the coral polyps and microscopic algae called zooxanthellae. These algae live within the coral's tissues and provide them with food through photosynthesis. In return, the coral provides the algae with a protected environment and access to sunlight. This partnership is crucial for the survival of both organisms and contributes to the overall health of the reef.
Coral reefs are incredibly important to the health of our oceans. They act as natural barriers, protecting coastlines from erosion and storm surges. They also provide a source of food and income for millions of people around the world. Fishing, tourism, and even medicine rely on the health and diversity of coral reefs.
Unfortunately, coral reefs are facing many threats, including pollution, overfishing, climate change, and destructive fishing practices. Rising ocean temperatures and ocean acidification are particularly damaging to coral reefs, causing them to bleach and die. Coral bleaching occurs when the symbiotic algae leave the coral, leading to a loss of color and eventually, the death of the coral.
Protecting coral reefs is crucial for the health of our oceans and the well-being of countless species. We can all do our part by reducing our carbon footprint, supporting sustainable seafood practices, and advocating for policies that protect these vital ecosystems. The future of coral reefs depends on our collective efforts to ensure their survival.$t$,
            303)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$What are coral reefs made of?$t$,
          jsonb_build_array($t$algae$t$, $t$anemones$t$, $t$calcium$t$, $t$polyps$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What is the main reason coral reefs are important to the health of our oceans?$t$,
          jsonb_build_array($t$They provide a source of food for humans.$t$, $t$They are a popular tourist destination.$t$, $t$They protect coastlines from erosion and storms.$t$, $t$They are home to a diverse array of marine life.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Why are coral reefs described as "underwater cities"?$t$,
          jsonb_build_array($t$Because they are made of hard structures like buildings.$t$, $t$Because they are home to a large population of organisms.$t$, $t$Because they are in deep, dark parts of the ocean.$t$, $t$Because they are a popular tourist destination.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$What can be inferred about the relationship between coral polyps and zooxanthellae?$t$,
          jsonb_build_array($t$They are competitors for resources.$t$, $t$They are predators and prey.$t$, $t$They are mutually beneficial partners.$t$, $t$They have no significant impact on each other.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$What is an indirect consequence of coral bleaching?$t$,
          jsonb_build_array($t$death of coral reefs and other marine life$t$, $t$erosion of coast lines and storm surges$t$, $t$loss of vibrant colors of the coral reefs$t$, $t$warmer ocean temperatures and acidity$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$What is the author's main purpose in writing this passage?$t$,
          jsonb_build_array($t$To describe the physical characteristics of coral reefs$t$, $t$To explain the scientific process of coral formation$t$, $t$To highlight the importance of protecting coral reefs$t$, $t$To provide a detailed history of coral reefs$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$How did the author organize the ideas in the selection?$t$,
          jsonb_build_array($t$by describing events leading to coral reefs destruction$t$, $t$by explaining problems pertaining to coral reefs$t$, $t$by listing relevant information about coral reefs$t$, $t$by showing how some events badly affect coral reefs$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$The passage states that coral reefs are "vital to the health of our oceans." What evidence supports this claim?
I. Coral reefs protect coastlines from erosion and storms.
II. Coral reefs are source of food for human beings.
III. Fish and other marine life live in coral reefs.
IV. Coral reefs have a symbiotic relationship with algae.$t$,
          jsonb_build_array($t$I and II$t$, $t$I and III$t$, $t$II, and IV$t$, $t$I and IV$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 9, null, $t$Which of the following best describes the last paragraph?$t$,
          jsonb_build_array($t$It is didactic, that is, it intended to teach.$t$, $t$It contains the main topic of the selection.$t$, $t$It has a very serious and formal tone.$t$, $t$It provides support to the ideas presented.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 10, null, $t$Which of the following is true about this article?$t$,
          jsonb_build_array($t$It appeals to environmentalists.$t$, $t$It describes the issue accurately.$t$, $t$It discusses a relevant issue.$t$, $t$It presents a recent problem.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- MoSYG08-RCH2: The Advent of Electric Cars (level 8, mosy; 220 words; printed 220)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 8 and title = $t$The Advent of Electric Cars$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'mosy', $t$RCH2$t$, 8, $t$The Advent of Electric Cars$t$,
            null,
            $t$A century ago, most vehicles on the road ran on gasoline. These cars emitted pollutants which were harmful to the environment and contributed to global warming. Electric vehicles, or EVs, were just a futuristic idea. The battery technology back then was not efficient enough to power cars for long distances, making gasoline-powered cars more practical for everyday use.
However, as concerns about the environment grew, scientists and engineers began to search for cleaner alternatives. The push for renewable energy sources led to advancements in battery technology. Soon, batteries could store more energy and be recharged faster. This opened the door for the production of practical electric cars that could compete with their gasoline counterparts.
The rise of the electric car led to many changes in the automobile industry. New companies emerged, dedicated solely to producing EVs. Traditional car companies had to adapt their production lines to incorporate electric models. Charging stations began to appear in cities, replacing or standing alongside gas stations.
The transition to electric cars also impacted the job market. New jobs, such as battery technicians and charging station operators, were created. On the other hand, some jobs related to the gasoline industry faced decline. The shift towards electric cars marked not only an evolution in transportation but also a significant change in society's approach to sustainable living.$t$,
            220)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$What type of fuel did most vehicles use a century ago?$t$,
          jsonb_build_array($t$Electricity$t$, $t$Gasoline$t$, $t$Solar power$t$, $t$Hydrogen$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$Why were electric vehicles considered impractical in the past?$t$,
          jsonb_build_array($t$They were too expensive to produce$t$, $t$Battery technology was inefficient for long distances$t$, $t$Gasoline was banned$t$, $t$Charging stations were everywhere$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$What technological advancement made electric cars more practical?$t$,
          jsonb_build_array($t$Faster engines$t$, $t$Renewable energy sources$t$, $t$Improved battery storage and faster recharging$t$, $t$Cheaper gasoline prices$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Which new infrastructure appeared alongside gas stations?$t$,
          jsonb_build_array($t$Solar panels$t$, $t$Charging stations$t$, $t$Wind turbines$t$, $t$Battery factories$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Why did scientists and engineers begin searching for cleaner alternatives to gasoline-powered cars?$t$,
          jsonb_build_array($t$To make cars faster$t$, $t$To reduce environmental pollution and global warming$t$, $t$To compete with traditional car companies$t$, $t$To increase fuel prices$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$What does the rise of electric cars suggest about society's priorities?$t$,
          jsonb_build_array($t$People value speed over sustainability$t$, $t$There is a growing concern for environmental protection$t$, $t$Gasoline is becoming more popular$t$, $t$Technology is slowing down$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$How did the transition to electric cars affect traditional car companies?$t$,
          jsonb_build_array($t$They stopped producing vehicles$t$, $t$They adapted their production lines to include electric models$t$, $t$They focused only on gasoline cars$t$, $t$They merged with battery companies$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$What could be a possible long-term effect of the decline in gasoline-related jobs?$t$,
          jsonb_build_array($t$Increased pollution$t$, $t$Growth in renewable energy careers$t$, $t$Decrease in electric car production$t$, $t$More reliance on fossil fuels$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 9, null, $t$If battery technology had not improved, what might have happened to electric cars?$t$,
          jsonb_build_array($t$They would have remained a futuristic idea$t$, $t$They would have replaced gasoline cars earlier$t$, $t$They would have become the main mode of transport$t$, $t$They would have caused more pollution$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 10, null, $t$Based on the text, which statement best reflects the author's viewpoint?$t$,
          jsonb_build_array($t$Electric cars are a temporary trend$t$, $t$The shift to electric cars is a major step toward sustainability$t$, $t$Gasoline cars are still the best option$t$, $t$Battery technology is unnecessary for progress$t$), 'b')
  on conflict (passage_id, question_no) do nothing;

  -- G8Post: The Impact of Social Media on Communication (level 8, post; 303 words)
  -- Key: booklet differs from the manual at Q3 d->b, Q4 d->c, Q8 c->d, Q9 d->b, Q10 b->c (manual -> booklet).
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 8 and title = $t$The Impact of Social Media on Communication$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', null, 8, $t$The Impact of Social Media on Communication$t$,
            null,
            $t$Social media has changed the way we communicate with each other. It is like having a big town square where everyone can share news and stories instantly. We can connect with friends and family members who can be on the far side of the globe. Social media through the Internet has figuratively made the world smaller. All one needs is a gadget. It may be a smart phone, a tablet, or a laptop. Desktops can still be used.
What is even amazing is that we can make friends from practically everywhere on the planet. And it is relatively easy to find common interests because we can easily make exchanges. We can choose to chat or make video calls using a platform of our choice. There's Messenger, Viber, and WhatsApp to name a few. Chatting has gone a long way since Yahoo Messenger and Skype. And if we want people to be updated about us, there is Facebook, Instagram, and X (formerly known as Twitter).
Personal communication is not the only one that changes. Even businesses turn to social media and digital networks to promote and sell their products and to connect with prospective clients and business partners. The Internet becomes a convenient venue for posting business ads as it has a wider reach.
But we are always warned about the dangers of communicating through the Internet. The information that we share becomes public and can be re-shared in either a positive or negative way. We have heard and read about people who become victims of malicious sharing of photos and videos.
While we enjoy the ease and convenience of communicating through social media, we should also be aware of these threats. Otherwise, there is always the possibility that we will be part of the statistics of those whose lives are destroyed by oversharing.$t$,
            303)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Why does social media "relatively made the world smaller"?$t$,
          jsonb_build_array($t$Family members can communicate anytime.$t$, $t$People can use digital gadgets to communicate.$t$, $t$One does not need to travel to meet people.$t$, $t$We can share news and stories instantly.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$In the second paragraph, what does exchanges mean?$t$,
          jsonb_build_array($t$Conversations$t$, $t$Pictures$t$, $t$Products$t$, $t$videos$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$What technique did the author use in communicating the message of the selection?$t$,
          jsonb_build_array($t$by describing a series of events that happened$t$, $t$by giving examples of social media platforms$t$, $t$by narrating events in a random manner$t$, $t$by using ordinary and familiar terms$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Which of the following information is relevant to the discussion of social media in the selection?$t$,
          jsonb_build_array($t$being aware of privacy issues in social media$t$, $t$choosing the right kind of social media$t$, $t$communicating using social media$t$, $t$knowing what to post in social media$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Which of the following can be concluded about this article?$t$,
          jsonb_build_array($t$Every technological advancement has its advantages and disadvantages.$t$, $t$Internet, especially social media has become an important part of our lives.$t$, $t$People would always discover ways of improving the way they communicate.$t$, $t$The way we communicate today is far different from the way we communicate before.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Which of the following is NOT discussed in the selection?$t$,
          jsonb_build_array($t$the convenience of using different types of social media platforms$t$, $t$the importance of using digital gadgets in communicating$t$, $t$the statistics of people victimized in Internet related communication$t$, $t$the types of communication that take place on the Internet$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$What is the importance of the last paragraph?$t$,
          jsonb_build_array($t$It contains the topic sentence.$t$, $t$It presents a summary of the article.$t$, $t$It suggests an action to the issue.$t$, $t$It supports the discussions in the article.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$Who will benefit from reading this article?$t$,
          jsonb_build_array($t$People who advertise their products in social media$t$, $t$People who like making friends through social media$t$, $t$People who love posting about their activities in social media$t$, $t$People who use social media to talk to families abroad$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 9, null, $t$What is the general tone of this article?$t$,
          jsonb_build_array($t$Critical- scrutinizes or judges the subject matter$t$, $t$Didactic-aims to educate or instruct the reader$t$, $t$Scholarly-tone is academic and intellectual; formal$t$, $t$Straightforward-present information clearly and simply$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 10, null, $t$What is the main purpose of the article?$t$,
          jsonb_build_array($t$To inform the readers about the increasing number of people destroyed by social media.$t$, $t$To persuade the readers to be more careful about what they share in social media$t$, $t$To remind the readers how social media has influenced the way we communicate$t$, $t$To tell the readers about the ease and convenience of using social media$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- G9Pre: Tesla's AI Robot Ready in September (level 9, pre; 258 words)
  -- Key: booklet differs from the manual at Q1 a->b, Q4 c->a, Q6 a->b, Q10 a->c (manual -> booklet).
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 9 and title = $t$Tesla's AI Robot Ready in September$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', null, 9, $t$Tesla's AI Robot Ready in September$t$,
            null,
            $t$Elon Musk, CEO of Tesla, asserts that the "Optimus" humanoid AI robot was about to be released on September 30, 2022. It was initially scheduled for release on Tesla Day, August 19, but was delayed until September. The delay was caused by the possibility that a prototype of the AI robot would be available by that time.
The humanoid AI robot from Tesla was first announced in August of 2021. It was designed to assist and do daily human tasks. It can walk at least 5 miles per hour and lift 150 pounds. According to Tesla, Optimus can "eliminate dangerous, boring, and repetitive tasks."
Tesla is a well-known automaker that believes electric vehicles can be better, faster, and more enjoyable to drive than gasoline-powered vehicles. Tesla, which makes self-driving cars powered by artificial intelligence, used artificial intelligence for the first time to create a humanoid robot. Japan and China, two of the world's leading artificial intelligence competitors, have yet to develop a humanoid that physically resembles humans and can perform human functions. Optimus will be the first to perform tasks humans do not prefer or want to do. It can also adapt to its owner's personality. To personalize Optimus, the owner can somehow transfer his or her traits to it.
The launch of this humanoid would be the first of its type, and a great deal of anticipation surrounds the event. Due to Tesla's vow to use artificial intelligence to improve technology for the greater benefit, many people have high hopes for the future success of this robot.$t$,
            258)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Which of the following can Tesla's AI robot do for humans?$t$,
          jsonb_build_array($t$cook$t$, $t$drive$t$, $t$run$t$, $t$think$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What can owners do to make the AI robot more personalized?$t$,
          jsonb_build_array($t$Owners can change its appearance.$t$, $t$Owners can customize its appearance.$t$, $t$Owners can give it a name.$t$, $t$Owners can pass on characteristics.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$What would be the possible impact of Tesla's AI robot on people's lives?$t$,
          jsonb_build_array($t$It will make people's lives more advanced.$t$, $t$It will make people's lives more beautiful.$t$, $t$It will make people's lives more comfortable.$t$, $t$It will make people's lives more complicated.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$What is implied by the statement, "Japan and China, two of the world's leading artificial intelligence competitors, have yet to develop a humanoid that physically resembles humans and can perform human functions"?$t$,
          jsonb_build_array($t$America has overtaken Japan and China in artificial intelligence competition.$t$, $t$America, Japan, and China were the three leading competitors in robot making.$t$, $t$Japan and China will also develop a humanoid robot-like Optimus.$t$, $t$Japan ang China will envy America for being able to develop a humanoid robot.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Which of the following is NOT discussed in the selection?$t$,
          jsonb_build_array($t$Artificial intelligence is becoming useful to people.$t$, $t$Modern technology can benefit everyone who can afford.$t$, $t$Technological advancement will always be beneficial.$t$, $t$Technology will always have good and bad effects.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$What is the meaning of the word "anticipation" in this sentence? The launch of this humanoid would be the first of its type, and a great deal of anticipation surrounds the event.$t$,
          jsonb_build_array($t$eagerness$t$, $t$expectation$t$, $t$prediction$t$, $t$suspension$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$What disadvantage may Optimus cause?$t$,
          jsonb_build_array($t$People may become lazy.$t$, $t$People may harm nature.$t$, $t$People may not be healthy.$t$, $t$People may not think anymore.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$Which of the following sentences is an opinion expressed in the selection?$t$,
          jsonb_build_array($t$Tesla's Optimus promises an incomparable AI advancement.$t$, $t$Tesla's Optimus will be able to adapt to the personality of its owner.$t$, $t$Tesla's Optimus will be capable of performing human functions.$t$, $t$Tesla's Optimus will be released on September 30, 2022.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 9, null, $t$What is the author's purpose in writing the text?$t$,
          jsonb_build_array($t$To compare America with Japan and China$t$, $t$To entertain people with a robot story$t$, $t$To inform about the latest AI invention$t$, $t$To persuade the people to buy robots$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 10, null, $t$Which of the following is NOT mentioned in the article?$t$,
          jsonb_build_array($t$disadvantages of the AI robot$t$, $t$distribution details of the Ai robot$t$, $t$estimate price of the AI robot$t$, $t$manufacturers of the AI robot$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- MoSYG09-RC17: The Hidden Language of Trees (level 9, mosy; 279 words; printed 279)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 9 and title = $t$The Hidden Language of Trees$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'mosy', $t$RC17$t$, 9, $t$The Hidden Language of Trees$t$,
            null,
            $t$Trees, often viewed as silent and unchanging sentinels of our landscape, have secrets they've kept for millennia. Recent scientific discoveries have started to decode the hidden communications between trees, revealing an underground network often referred to as the "Wood Wide Web."
Researchers at the Forest Ecology Lab in Zurich embarked on a detailed study to understand how trees in a forest communicate with one another. Using advanced sensors and monitoring techniques, they discovered that trees exchange nutrients, water, and chemical signals through mycorrhizal fungi— a complex web of interconnected roots and fungal networks.
When a tree is under stress, be it from a lack of water or an infestation of pests, it sends out distress signals. These are detected by neighboring trees, which respond by sending resources or defensive chemicals to help the afflicted tree. For instance, when a particular tree is attacked by insects, it might release specific chemical compounds. Nearby trees pick up on these signals and start producing their own defensive chemicals to ward off the impending threat.
What's even more fascinating is that older, "mother trees" seem to play a central role in these forest networks. These ancient trees, having vast connections, act as reservoirs of knowledge and resources. They support younger trees by sharing nutrients and offering them better chances of survival.
Scientists believe that understanding this intricate communication could revolutionize forest conservation efforts. By preserving the old and facilitating the growth of the new, we can ensure that forests remain resilient and robust ecosystems for generations to come. The revelations about the silent conversations happening beneath our feet challenge our understanding of trees as solitary beings and showcase the deep interconnectedness of nature.$t$,
            279)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$What term is used to describe the underground network that connects trees?$t$,
          jsonb_build_array($t$Tree Net$t$, $t$Root Web$t$, $t$Forest Grid$t$, $t$Wood Wide Web$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What do trees exchange through mycorrhizal fungi?$t$,
          jsonb_build_array($t$Bark and leaves$t$, $t$Only water$t$, $t$Nutrients, water, and chemical signals$t$, $t$Sunlight and oxygen$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Which trees play a central role in supporting younger trees?$t$,
          jsonb_build_array($t$Saplings$t$, $t$Mother trees$t$, $t$Fallen logs$t$, $t$Shrubs$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Why might older trees be considered 'reservoirs of knowledge'?$t$,
          jsonb_build_array($t$They prevent soil erosion$t$, $t$They store water for the forest$t$, $t$They produce more oxygen than younger trees$t$, $t$They have vast connections and share resources$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$What does the author imply about the nature of trees?$t$,
          jsonb_build_array($t$Trees are solitary beings$t$, $t$Trees compete aggressively for resources$t$, $t$Trees cooperate and communicate for survival$t$, $t$Trees depend only on sunlight$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Which statement best explains why trees release chemical signals when attacked by pests?$t$,
          jsonb_build_array($t$To attract more pests$t$, $t$To warn neighboring trees to prepare defenses$t$, $t$To stop photosynthesis$t$, $t$To increase fungal growth$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$If mother trees were removed from a forest, what would most likely happen?$t$,
          jsonb_build_array($t$Trees would grow faster due to more sunlight$t$, $t$Younger trees would thrive without competition$t$, $t$Communication among trees would improve$t$, $t$The forest network would weaken, reducing survival chances$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$Which conclusion can be drawn about forest ecosystems from the passage?$t$,
          jsonb_build_array($t$They are fragile and interconnected$t$, $t$They rely only on rainfall for survival$t$, $t$They are unaffected by human activity$t$, $t$They function independently without cooperation$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 9, null, $t$How could understanding tree communication help in conservation efforts?$t$,
          jsonb_build_array($t$By preserving old trees to maintain ecosystem resilience$t$, $t$By encouraging deforestation for better soil$t$, $t$By reducing fungal networks in forests$t$, $t$By planting only fast-growing species$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 10, null, $t$Imagine a city wants to mimic forest resilience. Which strategy aligns with the passage?$t$,
          jsonb_build_array($t$Build isolated parks with no plant interaction$t$, $t$Create green corridors that allow plant connectivity$t$, $t$Plant trees without considering soil fungi$t$, $t$Use artificial trees for decoration only$t$), 'b')
  on conflict (passage_id, question_no) do nothing;

  -- MoSYG09-RCI12: The Social Labyrinth of High School (level 9, mosy; 485 words; printed 485)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 9 and title = $t$The Social Labyrinth of High School$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'mosy', $t$RCI12$t$, 9, $t$The Social Labyrinth of High School$t$,
            null,
            $t$High school is often seen as a time of self-discovery and growth, but it can also be a period of social challenges and pressures. A recent study by the Adolescent Development Research Group at Riverdale University aimed to understand the complexities of high school social dynamics and their impact on teenagers.
The study, conducted over two academic years, involved observing and interviewing students from various high schools. Researchers focused on the different social groups, the unwritten rules governing interactions, and the impact of these dynamics on individual students.
One of the key findings was the existence of distinct social hierarchies within the high school environment. Students often found themselves navigating a complex social ladder, where popularity played a significant role. The study identified various groups, such as athletes, academics, artists, and those who did not clearly fit into any specific group. Each group had its own set of norms and expectations, which sometimes led to clashes and misunderstandings.
The research also highlighted the pressure to conform. Students often felt the need to fit into these groups, sometimes changing their behavior, interests, and even appearance to be accepted. This pressure was particularly intense for freshmen, who were still trying to find their place in the high school ecosystem.
Another significant aspect was the role of social media in amplifying these social dynamics. Platforms like Instagram and Snapchat became arenas for showcasing popularity and influence. The study found that social media often exacerbated feelings of exclusion and inadequacy among students who felt they did not measure up to their peers.
Bullying and exclusion were also prevalent themes in the study. Students from less popular groups reported feeling marginalized and sometimes bullied by their peers. This behavior was not always overt; it often took the form of social exclusion or spreading rumors.
However, the study also found positive aspects of high school social life. Many students found supportive communities within their groups. Extracurricular activities, like sports teams, clubs, and arts programs, provided opportunities for students to pursue their interests and form friendships based on shared passions rather than social hierarchies.
The impact of these social dynamics on academic performance and mental health was significant. Students who felt socially secure tended to perform better academically and show higher levels of happiness and self-esteem. In contrast, those who struggled with social challenges often experienced anxiety, depression, and a drop in academic performance.
The Adolescent Development Research Group concluded that while high school social dynamics can be challenging, they also offer opportunities for growth and learning. The researchers emphasized the importance of creating inclusive school environments where all students feel valued and accepted. They also highlighted the role of educators and parents in supporting students through these formative years.
The study sheds light on the complex social world of high school, underscoring the importance of understanding and addressing the challenges faced by adolescents in navigating this crucial stage of their lives.$t$,
            485)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$What was the main focus of the study mentioned in the text?$t$,
          jsonb_build_array($t$Academic performance only$t$, $t$Social dynamics and their impact on teenagers$t$, $t$The role of teachers in high school$t$, $t$The effect of extracurricular activities$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$Which social groups were identified in the study?$t$,
          jsonb_build_array($t$Athletes, academics, artists, and ungrouped students$t$, $t$Teachers, parents, and administrators$t$, $t$Freshmen and seniors only$t$, $t$Students who use social media$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$What role did social media play according to the study?$t$,
          jsonb_build_array($t$It reduced feelings of exclusion$t$, $t$It amplified social hierarchies and feelings of inadequacy$t$, $t$It eliminated bullying$t$, $t$It improved face-to-face communication$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Why did freshmen feel intense pressure in high school?$t$,
          jsonb_build_array($t$They wanted to join extracurricular activities$t$, $t$They were still trying to find their place in the social hierarchy$t$, $t$They disliked social media$t$, $t$They were excluded from classes$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$What can be inferred about students who felt socially secure?$t$,
          jsonb_build_array($t$They performed worse academically$t$, $t$They showed higher levels of happiness and self-esteem$t$, $t$They avoided extracurricular activities$t$, $t$They were less active on social media$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Why does the author mention extracurricular activities?$t$,
          jsonb_build_array($t$To show they increase bullying$t$, $t$To highlight opportunities for forming friendships based on shared interests$t$, $t$To prove they reduce academic performance$t$, $t$To suggest they are mandatory for all students$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$If social media use were banned in high schools, what might happen?$t$,
          jsonb_build_array($t$Social hierarchies would completely disappear$t$, $t$Feelings of exclusion might lessen, but other pressures could remain$t$, $t$Bullying would increase dramatically$t$, $t$Students would stop forming social groups$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$Which conclusion best reflects the author's viewpoint?$t$,
          jsonb_build_array($t$High school social dynamics are simple and easy to navigate$t$, $t$Social challenges can affect mental health and academic success$t$, $t$Social media has no influence on high school life$t$, $t$Teachers are solely responsible for students' happiness$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 9, null, $t$If you were a school administrator, which strategy would best address the issues raised in the text?$t$,
          jsonb_build_array($t$Encourage students to join only academic clubs$t$, $t$Create inclusive programs and educate students on healthy social media use$t$, $t$Ban all extracurricular activities$t$, $t$Promote competition among social groups$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 10, null, $t$How could parents help reduce the negative impact of social hierarchies?$t$,
          jsonb_build_array($t$By ignoring their child's social struggles$t$, $t$By guiding teens on balancing online and offline interactions$t$, $t$By encouraging them to avoid friendships$t$, $t$By limiting all forms of communication$t$), 'b')
  on conflict (passage_id, question_no) do nothing;

  -- G9Post: The Rise of AI in Education (level 9, post; 495 words)
  -- Key: booklet differs from the manual at Q6 a->b, Q7 c->d, Q10 a->c (manual -> booklet).
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 9 and title = $t$The Rise of AI in Education$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', null, 9, $t$The Rise of AI in Education$t$,
            null,
            $t$Artificial Intelligence or AI refers to technologies and systems that can accomplish tasks that typically require human intelligence, such as understanding language, recognizing patterns, and solving problems. AI has come across both major opportunities and notable challenges within the education framework.
Personalized learning is AI's main benefit. Students' performances can be analyzed by an AI-based platform, which would then determine their learning styles, strengths and weaknesses and adjust the teachings based on the evaluation. This is the situation where a student needs further preparation or lessons on a particular subject where they are struggling. This increases the effectiveness and inclusivity of education by enabling students to learn at their own pace. AI also saves teachers time because it allows them to grade papers automatically, manage calendars, and even respond to basic student questions that would otherwise need a significant amount of their valuable time to do for educational purposes.
There are also some disadvantages when using AI in teaching. For one, dependence by students on AI can cause delay in their abilities to engage in critical and creative thinking as well as in solving problems. If AI provides solutions too readily or too quickly, it is easy for the students to miss out on the learning process. Thirdly, AI does not carry human emotional intelligence invested in the classroom by a human teacher. It responds or gives instant feedback on students' work without giving encouragement in the same manner a teacher would, empathy in the same way a teacher would, or understanding-which are all elements of learning.
It is common knowledge that AI has the ability to transform education through individualized training, adaptive evaluations, and increased administrative efficiency. AI-powered technologies have the capacity to assess vast volumes of student data in order to customize learning routes and instructional materials, potentially increasing student engagement and academic performance. AI can also improve accessibility by offering real-time translation and accommodations for students with disabilities, hence increasing inclusivity in learning environments throughout the globe.
The possible disadvantages of AI in education as well as ethical issues are causes for concern. Adopting an excessive amount of AI, according to critics, might lessen the value of human teachers, who facilitate the face-to-face interactions necessary for comprehensive education. It is also important to give serious consideration to concerns like data privacy, biased grading systems, and the digital divide--where not everyone has equal access to AI tools.
Despite all these adverse challenges brought forth by AI on education, there are exciting possibilities. This might also lead to engagement through interactive tools, personalization of learning experiences, and useful information to help in improving teaching strategies. The challenge ahead is one of how AI can be added in a way that is harmonizing rather than replacing the essential human dimensions of teaching and learning. Finally, it will be subject to on how we find a balance between innovation in technology and keeping at the core of education the critical role teachers play in student growth.$t$,
            495)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$What is the meaning of the word "personalization" in the second stanza?$t$,
          jsonb_build_array($t$AI provides teachers information about how individual students learn.$t$, $t$AI saves working time for teachers so they can focus on teaching.$t$, $t$Students can choose the subjects that they like best.$t$, $t$Students have a lot of time to prepare for the different subjects.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$According to the selection, which of the following teacher activity is facilitated by AI?$t$,
          jsonb_build_array($t$developing the curriculum$t$, $t$designing students' assessment$t$, $t$grading students' assignment$t$, $t$teaching difficult topics$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$How does AI influence the teaching process?$t$,
          jsonb_build_array($t$AI contributes to instructional decision making.$t$, $t$AI makes the teachers' role in class repetitive.$t$, $t$AI replaces the teacher with so many teaching tasks.$t$, $t$AI supports the execution of automated tasks.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$According to the selection, why would AI cause education inequalities?$t$,
          jsonb_build_array($t$AI is inaccessible to students who have limited resources.$t$, $t$AI provides students from rural areas with richer resources.$t$, $t$AI puts more workload on disadvantaged students.$t$, $t$AI systems are too complicated to use for struggling students.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Which of the following is true about Artificial Intelligence?$t$,
          jsonb_build_array($t$It created limitless possibilities for both learning and teaching process.$t$, $t$It enhanced the ability to engage in critical and creative thinking.$t$, $t$It has the potential to replace teachers as facilitators of learning.$t$, $t$It makes learning and teaching faster than the way it used to be.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Which of the following needs further explanation?$t$,
          jsonb_build_array($t$how AI benefits learners with disabilities$t$, $t$how AI causes delay in ability to think$t$, $t$how AI helps teachers to save time$t$, $t$how transforms the learning process$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$What is the author suggesting in the last paragraph?$t$,
          jsonb_build_array($t$to continue using AI in the classroom$t$, $t$to fight the challenges brought forth by AI$t$, $t$to help teachers improve their AI knowledge$t$, $t$to identify the role that teachers play in using AI$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$Which of the following is used by the author in organizing ideas in one of the paragraphs?$t$,
          jsonb_build_array($t$describing common knowledge about AI$t$, $t$emphasizing the importance of data privacy$t$, $t$enumerating the disadvantages of using AI$t$, $t$giving examples of AI based platforms$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 9, null, $t$What is the general tone of the selection?$t$,
          jsonb_build_array($t$didactic-teaching readers what to do$t$, $t$objective-unbiased, neutral, fact-based$t$, $t$urgent-creates a sense importance$t$, $t$serious- urgent, not intended to entertain$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 10, null, $t$Which is NOT discussed in the selection?$t$,
          jsonb_build_array($t$how AI can increase administrative efficiency$t$, $t$how AI can promote inclusivity of learning$t$, $t$how AI serves ad hindrance to in person learning$t$, $t$how AI benefits struggling students$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- G10Pre: Butuan Archeological Sites (level 10, pre; 347 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 10 and title = $t$Butuan Archeological Sites$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', null, 10, $t$Butuan Archeological Sites$t$,
            null,
            $t$In 1975, as a result of the construction of an extensive network of large drainage channels, or esteros, to relieve Butuan City from destructive annual floods, significant amounts of archaeological artifacts were discovered that dated back to the Age of Contact with the Great Traditions of Asia, coeval with the Yueh type wares to Ming Dynasties of ancient China from the 10th Century to the 16th Century AD.
The major find in various areas is the appearance of the remains of large open-water-going boats, the "balanghai" of historical records. The same type of boats and construction has been recovered in Sumatra and Pontian in Malaysia, apparently of the same period. There are eleven of these boats: three were fully excavated, two preserved, and the rest are still unexcavated. The boats are of Neolithic architecture using a planking edge-peg technology. The boats range in age from the 10th to the 13th century AD.
The other significant sites yielded multiple interred wooden coffin burials, containing secondary burials that feature modified skulls that are frontally flattened, ascribed to the 14th-15th Century AD. Similar finds in Central Philippines have yielded similar burials but with the difference that all these were found in caves along the island's coasts.
The third significant feature of the stratified sites are the tremendous amounts of trade high-fired ceramics coming from China, Cambodia, Thailand, and other southeast Asian countries, as well as the distinctive white stamped pottery from Thailand; and Persian glassware, suggesting prehistoric links as far as the Middle East.
There were other notable discoveries like the Ivory Seal and the Silver Paleograph. Gold and tools for gold processing of ornaments have also been recovered from a village site. Over a hundred clay crucibles and tools for the processing of gold items were discovered in the area, leading to the conclusion that an extensive gold ornaments industry was in these areas as far back as a thousand years ago.
Altogether, these data demonstrate that Butuan was a thriving international trading port a thousand years ago, this site has a tremendous historical impact in the Asian region.$t$,
            347)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$What was the reason behind the construction of an extensive network of large drainage channels in Butuan in 1975?$t$,
          jsonb_build_array($t$to discover significant amounts of archaeological artifacts$t$, $t$to enhance the drainage system against damaging floods$t$, $t$to excavate the remains of large open-water-going boats$t$, $t$to unearth proofs of historical trading in the Asian region$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What does "esteros" mean in the first paragraph?$t$,
          jsonb_build_array($t$a network of large drainage channels$t$, $t$a result of an extensive construction$t$, $t$a number of archaeological artifacts$t$, $t$an effect of destructive annual floods$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Which of the following will benefit from the discovery of the archeological artifacts?$t$,
          jsonb_build_array($t$art, tradition, and industry$t$, $t$culture, history, and tradition$t$, $t$history, archeology, industry$t$, $t$tradition, architecture, art$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Which paragraph talked about the sites of wooden coffin burials?$t$,
          jsonb_build_array($t$paragraph 2$t$, $t$paragraph 3$t$, $t$paragraph 4$t$, $t$paragraph 5$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Which of the following is NOT implied in the selection?$t$,
          jsonb_build_array($t$The early Filipinos did business with countries in Asia.$t$, $t$The early Filipinos engaged in different types of trading.$t$, $t$The early Filipinos had great traditions.$t$, $t$The early Filipinos had knowledge of technology.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Which academic discipline or field of study does the topic of this text fall under?$t$,
          jsonb_build_array($t$Anthropology$t$, $t$Engineering$t$, $t$Ethnography$t$, $t$Psychology$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$Which of the following should be consulted regarding the discovery?$t$,
          jsonb_build_array($t$Department of Environment and Natural Resources$t$, $t$National Commission for Culture and the Arts$t$, $t$National Historical Commission of the Philippines$t$, $t$National Museum of the Philippines$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$Which type of paragraph development is used in the second paragraph to talk about "Balanghai"?$t$,
          jsonb_build_array($t$Descriptive paragraph$t$, $t$Literary paragraph$t$, $t$Narrative paragraph$t$, $t$Persuasive paragraph$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 9, null, $t$How did the author conclude the text?$t$,
          jsonb_build_array($t$A massive gold ornaments industry already existed a thousand years ago.$t$, $t$Butuan was a thriving international trading harbor a thousand years ago.$t$, $t$Wooden coffin burials in Butuan are similar to that in Central Philippines.$t$, $t$Discovered artifacts are dated back to the Age of Great Traditions of Asia.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 10, null, $t$Which of the following statements is NOT stated in the given text?$t$,
          jsonb_build_array($t$Butuan exported high-fired ceramics to China and stamped pottery to Thailand.$t$, $t$The Balanghai is of Neolithic architecture using a planking edge-peg technology.$t$, $t$There is a significant amount of archaeological artifacts found in Butuan.$t$, $t$Wooden coffins contained burials that feature frontally flattened modified skulls.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;

  -- MoSY10-RCJ1: The Influence of Social Media on Society (level 10, mosy; 283 words; printed 283)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 10 and title = $t$The Influence of Social Media on Society$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'mosy', $t$RCJ1$t$, 10, $t$The Influence of Social Media on Society$t$,
            null,
            $t$The rise of social media platforms has transformed the way we interact, communicate, and consume information. We will now explore the impact of social media on society, touching upon various aspects of this ever-evolving digital landscape.
Some argue that social media has brought people closer together, connecting friends and family across distances and facilitating the exchange of ideas. It has allowed individuals to share their thoughts and experiences in real-time, creating a sense of global interconnectedness.
However, critics contend that social media can be a double-edged sword. They argue that it can foster a sense of superficiality and obsession with image, leading to anxiety and self-esteem issues among users. The pressure to present a curated, idealized version of one's life can be detrimental to mental health, particularly among young people.
Another concern revolves around the spread of misinformation and fake news on social media platforms. Some individuals misuse these platforms to disseminate false information, potentially influencing public opinion and decision-making. The rapid spread of misinformation can have far-reaching consequences, including in the realm of politics and public health.
On the other hand, social media has proven to be a powerful tool for social and political movements. It has been instrumental in organizing protests, raising awareness about important issues, and mobilizing individuals for social change.
In conclusion, social media has become an integral part of modern society, offering both opportunities and challenges. While it has the potential to connect people, empower movements, and facilitate communication, it also poses risks to mental health and the dissemination of false information. It is essential for users to navigate the world of social media critically and responsibly, understanding the implications of their digital actions on society and themselves.$t$,
            283)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$According to the text, what is one argument in favor of social media's positive impact?$t$,
          jsonb_build_array($t$It creates a sense of superficiality.$t$, $t$It allows individuals to share thoughts in real-time.$t$, $t$It spreads misinformation rapidly.$t$, $t$It limits face-to-face communication.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$The text suggests that the pressure to present an idealized life online is most harmful to which group?$t$,
          jsonb_build_array($t$Politicians$t$, $t$Social media companies$t$, $t$Young people$t$, $t$News organizations$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Based on the text, which of the following is the most likely consequence of widespread misinformation on social media?$t$,
          jsonb_build_array($t$Increased in-person social gatherings$t$, $t$Erosion of trust in public institutions and media$t$, $t$Improved mental health for frequent users$t$, $t$A guaranteed decrease in political activism$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$How does the structure of the passage support the author's purpose?$t$,
          jsonb_build_array($t$It presents only the benefits to persuade readers to use social media.$t$, $t$It lists chronological events in the history of social media.$t$, $t$It presents a balanced view of advantages and disadvantages to inform the reader.$t$, $t$It uses emotional stories to criticize social media companies.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$What has social media proven to be a powerful tool for, according to the text?$t$,
          jsonb_build_array($t$Eliminating all anxiety and self-esteem issues$t$, $t$Social and political movements$t$, $t$Stopping the exchange of ideas$t$, $t$Ensuring all shared information is factually correct$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$The author describes social media as a "double-edged sword." What does this imply about its nature?$t$,
          jsonb_build_array($t$It is exclusively dangerous and should be avoided.$t$, $t$Its effects are entirely positive and without risk.$t$, $t$It inherently possesses both significant benefits and potential harms.$t$, $t$It is a tool used only for cutting or dividing online communities.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$If a social media platform introduced a feature that prominently labeled verified factual information, which main concern from the text would it most directly address?$t$,
          jsonb_build_array($t$The pressure to present an idealized self$t$, $t$The spread of misinformation$t$, $t$The decline of offline interactions$t$, $t$The organization of political movements$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$Which proposed solution is most aligned with the passage's concluding argument about user responsibility?$t$,
          jsonb_build_array($t$Governments should permanently shut down all major social media platforms.$t$, $t$Users should passively consume content without questioning its source.$t$, $t$Users should actively check sources and consider the impact before sharing content.$t$, $t$Social media companies should force users to share their private lives.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 9, null, $t$What does the text say is "essential" for users in the conclusion?$t$,
          jsonb_build_array($t$To use social media for entertainment only.$t$, $t$To navigate social media critically and responsibly.$t$, $t$To avoid all forms of online political discussion.$t$, $t$To trust all information presented by popular accounts.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 10, null, $t$Integrating ideas from the text, which statement best summarizes the overall relationship between social media and society as presented?$t$,
          jsonb_build_array($t$A purely technological triumph with no societal downsides.$t$, $t$A neutral tool whose impact depends entirely on corporate policies.$t$, $t$A transformative force that presents a complex mix of empowering opportunities and serious societal risks.$t$, $t$A failed experiment that has damaged interpersonal communication beyond repair.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- MoSY10-RCJ6: The Evolution of Mystery: From Folk Tales to Poe's Mastery (level 10, mosy; 509 words; printed 510)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 10 and title = $t$The Evolution of Mystery: From Folk Tales to Poe's Mastery$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'mosy', $t$RCJ6$t$, 10, $t$The Evolution of Mystery: From Folk Tales to Poe's Mastery$t$,
            null,
            $t$In the tapestry of literary genres, mystery holds a place of intricate patterns and deep textures, woven through time with threads of human curiosity and the lure of the unknown. Edgar Allan Poe, often heralded as the father of the modern mystery story, is typically associated with the birth of this genre. However, like the mistaken attribution of horror's origin to Mary Shelley's "Frankenstein," the roots of mystery stretch back much further.
The seeds of mystery can be traced to the oral traditions of ancient civilizations. People have always been captivated by the unexplained, and stories of enigmatic events, puzzles, and uncaught criminals abounded in the communal fireside tales of old. These narratives were not merely for entertainment; they served as moral compasses and warnings against the dangers lurking in the shadows of their worlds.
As written language became more accessible, these oral tales transformed into written folklore. The ancient Greeks and Romans were masters of crafting tales that delved into human psychology and the complexities of crime and punishment. Yet, these stories often lacked a central figure dedicated to solving the mysteries presented, which is a hallmark of the genre as we recognize it today.
Enter Edgar Allan Poe in the 19th century, who, with a flourish of his pen, carved a niche for the detective story. His character, C. Auguste Dupin, became the prototype for future detectives— a figure of keen intellect and acute observation, traits that have become synonymous with the genre. In "The Murders in the Rue Morgue," Poe crafted not just a story, but a framework for mystery writing that involved a perplexing crime, a series of clues, red herrings, and an eventual resolution brought about by logical deduction.
While Poe did not invent the concept of mystery, his contributions to the genre were revolutionary. He introduced a structured approach to mystery storytelling that focused on the cerebral challenge of unraveling a conundrum. This was a marked shift from the more atmospheric and superstitious elements that had previously dominated tales of the unknown. Poe's stories emphasized the intellectual pleasure of piecing together the puzzle and the satisfaction of a mystery unraveled.
The impact of Poe's work on the genre is indisputable. His methodical construction of the detective story provided a blueprint that has been followed and refined by countless authors after him. Characters like Sherlock Holmes, Hercule Poirot, and Nancy Drew owe their existence to the foundation laid by Poe's innovative approach to mystery writing.
Thus, while it is tempting to point to a single source as the origin of a genre, the reality is far more complex. Just as Mary Shelley did not create horror, Edgar Allan Poe did not invent mystery. Instead, he took existing elements of storytelling that had captivated humans for centuries and wove them into a format that would become the standard for mystery narratives. It is through his masterful synthesis of the human fascination with the unknown and the joy of problem-solving that Poe earned his place as a pivotal figure in the evolution of the mystery genre.$t$,
            509)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Who is often regarded as the father of the modern mystery story?$t$,
          jsonb_build_array($t$Mary Shelley$t$, $t$Edgar Allan Poe$t$, $t$Arthur Conan Doyle$t$, $t$Agatha Christie$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What character created by Poe became the prototype for future detectives?$t$,
          jsonb_build_array($t$Sherlock Holmes$t$, $t$Hercule Poirot$t$, $t$Auguste Dupin$t$, $t$Nancy Drew$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$According to the text, what was the main purpose of oral mystery tales in ancient civilizations?$t$,
          jsonb_build_array($t$To entertain only$t$, $t$To serve as moral compasses and warnings$t$, $t$To teach people how to solve crimes$t$, $t$To introduce detective characters$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Which story by Poe is mentioned as an example of his structured approach to mystery writing?$t$,
          jsonb_build_array($t$"The Murders in the Rue Morgue"$t$, $t$"The Tell-Tale Heart"$t$, $t$"The Black Cat"$t$, $t$"The Raven"$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Why does the author compare Poe's contribution to mystery with Mary Shelley's association with horror?$t$,
          jsonb_build_array($t$To argue that Poe was more influential than Shelley$t$, $t$To suggest that horror and mystery share similar roots$t$, $t$To show that both genres originated in the 19th century$t$, $t$To emphasize that neither author invented their respective genres$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$What does the phrase "woven through time with threads of human curiosity" suggest about the mystery genre?$t$,
          jsonb_build_array($t$It is a recent development in literature$t$, $t$It has evolved gradually and is deeply connected to human nature$t$, $t$It is unrelated to human emotions$t$, $t$It is primarily based on scientific discoveries$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$Why does the author describe Poe's approach as a "marked shift" from earlier tales?$t$,
          jsonb_build_array($t$Poe eliminated suspense from mystery stories$t$, $t$Poe focused on supernatural elements$t$, $t$Poe introduced logical deduction and structured storytelling$t$, $t$Poe wrote only short stories$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$Which of the following best explains why Poe's work is considered revolutionary?$t$,
          jsonb_build_array($t$He created stories that were purely atmospheric and superstitious$t$, $t$He introduced a detective figure and logical problem-solving into mystery writing$t$, $t$He focused on horror rather than mystery$t$, $t$He wrote stories without any resolution$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 9, null, $t$If Poe had not introduced structured detective stories, what might have been the impact on modern mystery fiction?$t$,
          jsonb_build_array($t$Mystery stories would have remained focused on folklore and superstition$t$, $t$Mystery stories would have disappeared entirely$t$, $t$Horror stories would have become less popular$t$, $t$Oral traditions would have continued unchanged$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 10, null, $t$Based on the text, which statement best reflects the author's viewpoint about the origin of mystery?$t$,
          jsonb_build_array($t$Mystery was invented by Poe in the 19th century$t$, $t$Mystery evolved from ancient oral traditions and was refined by Poe$t$, $t$Mystery originated from Gothic horror stories$t$, $t$Mystery is a genre that has remained unchanged over time$t$), 'b')
  on conflict (passage_id, question_no) do nothing;

  -- G10Post: Exploring Non-Mendelian Genetics (level 10, post; 446 words)
  -- Key: booklet differs from the manual at Q5 b->a, Q6 a->c, Q7 d->c, Q9 c->a (manual -> booklet).
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 10 and title = $t$Exploring Non-Mendelian Genetics$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', null, 10, $t$Exploring Non-Mendelian Genetics$t$,
            null,
            $t$Non-Mendelian genetics encompasses inheritance patterns that deviate from the classical rules established by Gregor Mendel. Mendel's groundbreaking experiments with pea plants laid the foundation for understanding genetic inheritance through specific dominant and recessive alleles. However, this framework is limited, as many traits in living organisms exhibit more complex inheritance patterns. By exploring non-Mendelian concepts, we can gain a deeper appreciation for the diversity of genetic traits present in nature.
One significant form of non-Mendelian inheritance is incomplete dominance. In this pattern, the offspring display a phenotype that is a blend of the traits from both parents. For instance, crossing a red flower (RR) with a white flower (WW) results in a hybrid (RW) that is pink. This indicates that neither allele is completely dominant, leading to an intermediate expression of traits. This phenomenon shows how traits can combine in ways that do not fit into Mendelian categories.
Another concept within non-Mendelian genetics is codominance. Codominance occurs when both alleles in a heterozygous individual are fully expressed in the phenotype. A well-known example can be observed in certain breeds of chickens, where black feathers (B) and white feathers (W) are codominant. When a black chicken and a white chicken are cross-fertilized, the offspring display both black and white feathers. This demonstrates that both alleles contribute equally to the phenotype, resulting in distinct and observable traits.
Polygenic inheritance represents another non-Mendelian inheritance where multiple genes influence a single trait. Traits such as human height and skin color fall under this category, as they are controlled by several genes working together. This results in a wide range of phenotypes rather than distinct categories. For example, human height can vary significantly due to the cumulative effects of many different genes, illustrating the complexity of genetic inheritance beyond simple dominant-recessive relationships.
Additionally, extranuclear inheritance involves genes located outside the nucleus, primarily within mitochondria or chloroplasts. Mitochondrial DNA is inherited from the mother and can lead to specific traits or diseases that do not adhere strictly to Mendelian patterns. This type of inheritance provides insight into certain genetic conditions passed down through maternal lines and emphasizes the importance of understanding genetic transmission beyond nuclear DNA.
Understanding non-Mendelian genetics is crucial across various fields, including medicine, agriculture, and evolutionary biology. It offers valuable insights into complex traits and how they are inherited from one generation to the next. For example, recognizing that some genetic disorders may arise from multiple genes rather than a single gene can refine our approaches to treatment and prevention strategies. Overall, non-Mendelian genetics enriches our knowledge of heredity and helps explain the intricate tapestry of life's diversity, revealing how complex interactions shape the traits we observe in organisms today.$t$,
            446)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$What has the same meaning as the word diversity in the first paragraph?$t$,
          jsonb_build_array($t$concepts$t$, $t$patterns$t$, $t$types$t$, $t$variety$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$The situations inside illustrate different non-Mendelian inheritance patterns.
Which is an example of codominance pattern?$t$,
          jsonb_build_array($t$A child who inherited a combination of his mother (black) and father (white) skin.$t$, $t$A child who inherited the blue eyes of his mother and the curly hair of his father$t$, $t$A child who inherited the brown skin of his mother and the height of his father$t$, $t$A child who inherited diabetes from his mother who got it from her grandmother$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$The situations inside illustrate different non-Mendelian inheritance patterns.
Which is an example of incomplete dominance pattern?$t$,
          jsonb_build_array($t$A child who inherited a combination of his mother (black) and father (white) skin.$t$, $t$A child who inherited the blue eyes of his mother and the curly hair of his father$t$, $t$A child who inherited the brown skin of his mother and the height of his father$t$, $t$A child who inherited diabetes from his mother who got it from her grandmother$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$The situations inside illustrate different non-Mendelian inheritance patterns.
Which is an example of extranuclear inheritance pattern?$t$,
          jsonb_build_array($t$A child who inherited a combination of his mother (black) and father (white) skin.$t$, $t$A child who inherited the blue eyes of his mother and the curly hair of his father$t$, $t$A child who inherited the brown skin of his mother and the height of his father$t$, $t$A child who inherited diabetes from his mother who got it from her grandmother$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Which of the following is an example of codominance pattern?$t$,
          jsonb_build_array($t$a child who inherited a combination of his mother (black) and father (white) skin$t$, $t$a child who inherited the blue eyes of his mother and the curly hair of his father$t$, $t$a child who inherited the brown skin of his mother and the height of his father$t$, $t$a child who inherited diabetes from his mother who got it from her grandmother$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$What is the importance of knowing non-Mendelian genetics?$t$,
          jsonb_build_array($t$It challenges the classical rules of inheritance patterns established by Gregor Mendel.$t$, $t$It disproves the classical rules of inheritance patterns established by Gregor Mendel.$t$, $t$It expands the classical rules of inheritance patterns established by Gregor Mendel.$t$, $t$It improves the classical rules of inheritance patterns established by Gregor Mendel.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$What is the purpose of the selection?$t$,
          jsonb_build_array($t$to argue about Gregor Mendel's classic theories on genetics$t$, $t$to describe the different rules of inheritance patterns$t$, $t$to inform readers about the limitations of the Mendelian theory$t$, $t$to persuade readers to consider non-Mendelian inheritance patterns$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$Which of the following is NOT discussed in the selection$t$,
          jsonb_build_array($t$complexities of inheritance patterns$t$, $t$descriptions of genetic conditions$t$, $t$examples of non-Mendelian patterns$t$, $t$significance of genetic inheritance$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 9, null, $t$Which paragraph contains the topic sentence?$t$,
          jsonb_build_array($t$first paragraph$t$, $t$fourth paragraph$t$, $t$last paragraph$t$, $t$second paragraph$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 10, null, $t$How did the author organize the ideas in the selection?$t$,
          jsonb_build_array($t$by comparing and contrasting Mendelian and non-Mendelian rules of inheritance$t$, $t$by describing the characteristics of non-Mendelian genetic inheritance patterns$t$, $t$by inferring the cause and effects of the different inheritance patterns on people$t$, $t$by presenting the problems that humans may encounter because of genetic inheritance$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
end
$seed$;

-- Check (read-only): 41 passages (4 pre, 13 mosy, 4 post, 20 any round), 322 questions.
-- select p.level, coalesce(p.test_type, 'any') as round, p.set_code, p.title, p.word_count,
--        count(q.id) as questions
--   from public.phil_iri_passages p
--   join public.phil_iri_collections c on c.id = p.collection_id
--   left join public.phil_iri_questions q on q.passage_id = p.id
--  where c.school_id is null and c.name = $t$Phil-IRI Graded Passages (Level 2-10)$t$
--  group by p.id order by p.level, p.id;
