-- Phil-IRI 2018, English graded passages: pretest and posttest, Sets A-D, levels 2-7.
-- Source: Phil-IRI Full Package (DepEd, 2018), the teacher's copy of each set
-- (Appendices A9/A11 for titles, A10/A12 Key to Correction).
--
-- One region-wide, prescribed collection "Phil-IRI 2018", seeded INACTIVE: with
-- no test-type / reuse filter yet, Grades 4-7 would otherwise be offered every
-- set at once. Turn it on with the console
-- (phil-iri-collection-activate <id> on) when wanted; re-running this file never changes is_active of an
-- existing collection. Passages themselves are active, so one switch does it.
--
-- Levels 2 and 3 are seeded too (no BASA learner reads them today; Grades 4-10).
--
-- Left out: pretest Set D level 4 "Wake Up!". Both copies in the package print
-- the "On Market Day" text under that title while its questions are about
-- Toto's family and a fire; the real text is missing from the source.
--
-- Same passages as in "Phil-IRI JHS 2024" (the 2024 manual reuses them for
-- Grades 4-6): pretest C4 Anansi's Web, D5 Amy's Good Deed, D6 Dreams; posttest
-- C4 Marian's Experiment, C5 Trading Places, D6 Flying Rocks. They are separate
-- rows here, so a future no-reuse rule must not rely on passage ids alone.
--
-- Idempotent: run it in the SQL Editor (cloud) or on the LAN instance as often as
-- needed. Existing rows are left alone (a passage that has been read is locked
-- anyway); to correct a passage, edit it through the app or console.
--
-- Text: paragraphs are separated by a newline; lines are joined. Titles follow
-- the titles tables (the teacher's copy has typos such as "Rcosystems").
-- Dashes (printed as "--" or a soft hyphen) are an em dash attached to the word
-- before it, so each word stays one tap target and counts once.
--
-- Word counts: the 2018 package prints none; word_count is the number of
-- whitespace-separated words in the text as stored (PhilIriPassage.words).
--
-- Question types (literal/inferential/critical) are not given, so question_type
-- stays null. Answer keys are as printed; lines marked CHECK look wrong or need
-- the paper manual.
--
-- Contains nothing that bypasses RLS: created_by stays null when run without a
-- signed-in user (SQL Editor), as the stamp trigger allows.

do $seed$
declare
  c bigint;
  p bigint;
begin
  select id into c from public.phil_iri_collections
   where school_id is null and lower(name) = lower('Phil-IRI 2018');
  if c is null then
    insert into public.phil_iri_collections
      (school_id, name, description, is_prescribed, is_grade_leveled, has_comprehension, is_active)
    values (null, 'Phil-IRI 2018',
            'Phil-IRI (DepEd, 2018): English graded passages, pretest and posttest Sets A-D, levels 2-7.',
            true, true, true, false)
    returning id into c;
  end if;

  -- pre Set A, level 2: Pam's Cat (35 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'pre' and set_code = 'A' and level = 2;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', 'A', 2, $t$Pam's Cat$t$,
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

  -- pre Set A, level 3: Summer Fun (57 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'pre' and set_code = 'A' and level = 3;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', 'A', 3, $t$Summer Fun$t$,
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

  -- pre Set A, level 4: Get Up, Jacky! (67 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'pre' and set_code = 'A' and level = 4;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', 'A', 4, $t$Get Up, Jacky!$t$,
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

  -- pre Set A, level 5: Frog's Lunch (101 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'pre' and set_code = 'A' and level = 5;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', 'A', 5, $t$Frog's Lunch$t$,
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

  -- pre Set A, level 6: Yawning (130 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'pre' and set_code = 'A' and level = 6;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', 'A', 6, $t$Yawning$t$,
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
  -- CHECK: Q3 asks for the meaning of "involuntary", a word the passage does not use (it says "something that we cannot control"). Kept as printed.
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

  -- pre Set A, level 7: Dark Chocolate (152 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'pre' and set_code = 'A' and level = 7;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', 'A', 7, $t$Dark Chocolate$t$,
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

  -- pre Set B, level 2: A Hot Day (37 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'pre' and set_code = 'B' and level = 2;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', 'B', 2, $t$A Hot Day$t$,
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

  -- pre Set B, level 3: A Rainy Day (66 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'pre' and set_code = 'B' and level = 3;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', 'B', 3, $t$A Rainy Day$t$,
            $t$Which games do you play inside the house on a rainy day?
In the story, let's find out what game they will play.$t$,
            $t$Nina and Ria are looking out the window. "I do not like getting wet in the rain," says Nina.
"What can we do?" asks Ria. "We can play house," says Nina. "Or we can play tag," says Ria. "Okay, let's play tag. You're it!" says Nina. Nina runs from Ria and bumps a lamp.
"Oh no!" says Nina. "We must not play tag in the house."$t$,
            66)
    returning id into p;
  end if;
  -- CHECK: Q1 asks what RIA does not like, but in the passage it is Nina who does not like getting wet in the rain. Kept as printed.
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
          jsonb_build_array($t$Ria$t$, $t$Nina$t$, $t$Ria and Nina$t$), 'c')
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

  -- pre Set B, level 4: Waiting for the Peddler (69 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'pre' and set_code = 'B' and level = 4;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', 'B', 4, $t$Waiting for the Peddler$t$,
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

  -- pre Set B, level 5: The Cow and the Carabao (152 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'pre' and set_code = 'B' and level = 5;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', 'B', 5, $t$The Cow and the Carabao$t$,
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
          jsonb_build_array($t$They did not have time to rest.$t$, $t$They hardly saw each other.$t$, $t$They did not eat enough.$t$, $t$They were always tired.$t$), 'b')
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

  -- pre Set B, level 6: Laughter (142 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'pre' and set_code = 'B' and level = 6;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', 'B', 6, $t$Laughter$t$,
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

  -- pre Set B, level 7: Sneezing (152 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'pre' and set_code = 'B' and level = 7;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', 'B', 7, $t$Sneezing$t$,
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

  -- pre Set C, level 2: Al's Bag (28 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'pre' and set_code = 'C' and level = 2;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', 'C', 2, $t$Al's Bag$t$,
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

  -- pre Set C, level 3: Ben's Store (57 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'pre' and set_code = 'C' and level = 3;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', 'C', 3, $t$Ben's Store$t$,
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

  -- pre Set C, level 4: Anansi's Web (86 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'pre' and set_code = 'C' and level = 4;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', 'C', 4, $t$Anansi's Web$t$,
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
          jsonb_build_array($t$"My home is your home."$t$, $t$"Homes should be shared."$t$, $t$"There's no place like home. "$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- pre Set C, level 5: Pedrito's Snack (144 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'pre' and set_code = 'C' and level = 5;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', 'C', 5, $t$Pedrito's Snack$t$,
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

  -- pre Set C, level 6: Effects of Anger (162 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'pre' and set_code = 'C' and level = 6;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', 'C', 6, $t$Effects of Anger$t$,
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
          jsonb_build_array($t$being obedient$t$, $t$being honest$t$, $t$being thoughtful$t$, $t$being hardworking$t$), 'b')
  on conflict (passage_id, question_no) do nothing;

  -- pre Set C, level 7: Dust (185 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'pre' and set_code = 'C' and level = 7;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', 'C', 7, $t$Dust$t$,
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
          jsonb_build_array($t$how dust can be cleaned up$t$, $t$where the dust is coming from$t$, $t$what one might add to one's home$t$, $t$the lifestyle of the occupants$t$), 'd')
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
          jsonb_build_array($t$by giving examples$t$, $t$by narrating some events$t$, $t$by stating the cause and effect$t$, $t$by identifying the problem and the solutions$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$Which is an appropriate title of this selection?$t$,
          jsonb_build_array($t$Keeping the Houses Dust-Free$t$, $t$Sources of Dust in Our Homes$t$, $t$Effects of Dusty Homes$t$, $t$Diseases Due to Dust$t$), 'b')
  on conflict (passage_id, question_no) do nothing;

  -- pre Set D, level 2: Nat Takes a Nap (27 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'pre' and set_code = 'D' and level = 2;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', 'D', 2, $t$Nat Takes a Nap$t$,
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

  -- pre Set D, level 3: Waiting for Her Sister (58 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'pre' and set_code = 'D' and level = 3;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', 'D', 3, $t$Waiting for Her Sister$t$,
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

  -- pre Set D, level 5: Amy's Good Deed (106 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'pre' and set_code = 'D' and level = 5;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', 'D', 5, $t$Amy's Good Deed$t$,
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

  -- pre Set D, level 6: Dreams (141 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'pre' and set_code = 'D' and level = 6;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', 'D', 6, $t$Dreams$t$,
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
          jsonb_build_array($t$As we dream, we constantly think about what we have learned or experienced.$t$, $t$Our dreams help us focus on things we are unable to notice during the day.$t$, $t$Our brain comes up with solutions in our sleep.$t$, $t$Our brain sorts and files information.$t$), 'd')
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

  -- pre Set D, level 7: Pain (164 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'pre' and set_code = 'D' and level = 7;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', 'D', 7, $t$Pain$t$,
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
          jsonb_build_array($t$A baby crying at the sight of the needle$t$, $t$Drinking a pain killer once a headache starts$t$, $t$Asking if a dental procedure will hurt$t$, $t$We relive these experiences through our dreams$t$), 'b')
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

  -- post Set A, level 2: The Bib (33 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'post' and set_code = 'A' and level = 2;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', 'A', 2, $t$The Bib$t$,
            $t$Did you use a bib when you were a baby?
In the story, let's find out who uses a bib.$t$,
            $t$Bim-bim has a bib. It is from Tina. The bib is red. It is pretty.
But the bib is big. Will this fit?
"I will get a pin," says Dad. "There. It fits!"$t$,
            33)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Who has a bib?$t$,
          jsonb_build_array($t$Den-den$t$, $t$Bim-bim$t$, $t$Tin-tin$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What is the color of the bib?$t$,
          jsonb_build_array($t$red$t$, $t$pink$t$, $t$yellow$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Who gave the bib?$t$,
          jsonb_build_array($t$Dad$t$, $t$Mama$t$, $t$Tina$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$What is the problem with the bib?$t$,
          jsonb_build_array($t$It is big.$t$, $t$It is wet.$t$, $t$It has a rip.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$How did the bib fit Bim-bim?$t$,
          jsonb_build_array($t$Mama cut it.$t$, $t$Grandma fixed it.$t$, $t$Dad put a pin on it.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- post Set A, level 3: The Egg on the Grass (54 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'post' and set_code = 'A' and level = 3;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', 'A', 3, $t$The Egg on the Grass$t$,
            $t$Give me words that describe an egg.
What words describe the egg on the grass?$t$,
            $t$Duck, Hen, and Bird are in the garden. "I see a big, round egg on the grass," says Bird.
"It is not my egg," says Hen. "My egg is in the nest."
"It is not my egg," says Duck. "My eggs just hatched."
"It is not an egg," says Ben. "It's my rubber ball."$t$,
            54)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Where are Bird, Hen, and Duck?$t$,
          jsonb_build_array($t$in the nest$t$, $t$in the garden$t$, $t$in the farmhouse$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$Who saw the egg first?$t$,
          jsonb_build_array($t$the hen$t$, $t$the duck$t$, $t$the bird$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$What word tells about the egg?$t$,
          jsonb_build_array($t$big and round$t$, $t$white and shiny$t$, $t$tiny and colorful$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Who among the animals has a new baby?$t$,
          jsonb_build_array($t$the hen$t$, $t$the bird$t$, $t$the duck$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$What was the "egg" that the animals saw?$t$,
          jsonb_build_array($t$a large top$t$, $t$a rubber ball$t$, $t$a plastic cup$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Why did the animals think that the rubber ball is an egg?$t$,
          jsonb_build_array($t$It is tiny.$t$, $t$It is white.$t$, $t$It is round.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- post Set A, level 4: The Tricycle Man (77 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'post' and set_code = 'A' and level = 4;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', 'A', 4, $t$The Tricycle Man$t$,
            $t$Do you ride a tricycle?
In the story, who rode the tricycle?$t$,
            $t$Nick is a tricycle man. He waits for riders every morning. "Please take me to the bus station," says Mr. Perez. "Please take me to the market," says Mrs. Pardo. "Please take us to school," say Mike and Kris.
"But I can take only one of you," says Nick to the children. "Oh, I can sit behind you Nick," says Mr. Perez. "Kris or Mike can take my seat." "Thank you, Mr. Perez," say Mike and Kris.$t$,
            77)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Who is the tricycle man?$t$,
          jsonb_build_array($t$Mike$t$, $t$Nick$t$, $t$Mr. Perez$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What was Nick's problem?$t$,
          jsonb_build_array($t$There was a lot of traffic.$t$, $t$He could not take the children to school.$t$, $t$There was only one seat for either Kris or Mike.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$How many riders did the tricycle man have?$t$,
          jsonb_build_array($t$two$t$, $t$four$t$, $t$three$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Who helped solve Nick's problem?$t$,
          jsonb_build_array($t$Mr. Perez$t$, $t$Mrs. Pardo$t$, $t$another tricycle driver$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Which word describes Mr. Perez?$t$,
          jsonb_build_array($t$kind$t$, $t$strict$t$, $t$proud$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Which happened last?$t$,
          jsonb_build_array($t$Mr. Perez told Nick to take him to the bus station.$t$, $t$Mrs. Pardo told Nick to take her to the market.$t$, $t$Kris and Mike told Nick to take them to school.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- post Set A, level 5: The Snail with the Biggest House (96 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'post' and set_code = 'A' and level = 5;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', 'A', 5, $t$The Snail with the Biggest House$t$,
            $t$A snail carries its house on its back. What will happen if its house becomes too big and heavy?
In the story, find out: What happened to the snail with a very big house?$t$,
            $t$A little snail told his father, "I want to have the biggest house." "Keep your house light and easy to carry," said his father. But, the snail ate a lot until his house grew enormous. "You now have the biggest house," said the snails.
After a while, the snails have eaten all the grass in the farm. They decided to move to another place.
"Help! I cannot move," said the snail with the biggest house. The snails tried to help but the house was too heavy. So the snail with the biggest house was left behind.$t$,
            96)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$What kind of house did the father snail want the little snail to have?$t$,
          jsonb_build_array($t$big and tidy$t$, $t$hard and durable$t$, $t$large and colorful$t$, $t$light and easy to carry$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$The house grew enormous. A synonym of enormous is$t$,
          jsonb_build_array($t$huge$t$, $t$lovely$t$, $t$different$t$, $t$expensive$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Why will the snails move to another place?$t$,
          jsonb_build_array($t$Their enemies bother them$t$, $t$They want to see other places.$t$, $t$They have eaten all the grass in the farm.$t$, $t$They don't want to be with the snail with the biggest house.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$What was the little snail's problem when they were about to move?$t$,
          jsonb_build_array($t$"Will I build another house?"$t$, $t$"How can I carry my very big house?"$t$, $t$"What will happen to my biggest house?"$t$, $t$"What if another snail will have a house bigger than mine?"$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Why did the other snails leave the little snail behind?$t$,
          jsonb_build_array($t$He eats too much grass.$t$, $t$They did not want to be with him.$t$, $t$They could not move his very big house.$t$, $t$The little snail did not want to leave its house.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Which of the following did the little snail think at the end?$t$,
          jsonb_build_array($t$"My friends did not help me at all."$t$, $t$"I should have stored more grass and leaves in my house."$t$, $t$"Father was right. I should have a house that is easy to carry."$t$, $t$"Never mind if I stay behind. I have the biggest house anyway."$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$Which of the following will most likely happen to the little snail?$t$,
          jsonb_build_array($t$It will die of hunger.$t$, $t$It will destroy its house.$t$, $t$It will follow the other snails.$t$, $t$It will live happily in the farm.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;

  -- post Set A, level 6: Rocks from Outer Space (137 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'post' and set_code = 'A' and level = 6;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', 'A', 6, $t$Rocks from Outer Space$t$,
            $t$Have you seen a falling star? Where does it come from?
As you read the selection, find out where a falling star comes from.$t$,
            $t$The pieces of rocks that come from outer space have three names: meteor, meteorite, and meteoroid.
A meteoroid is a piece of matter moving in space. It moves as fast as 40 miles a second. It may be large or small. Most meteoroids are smaller than a grain of sand.
As a meteoroid comes into the air near the earth, it catches fire. Most meteoroids burn up before they hit the earth. The flash of light from the burning meteoroid is called a meteor. If a piece of meteoroid falls to the ground, it is called a meteorite.
People have studied these rocks for many years. They wanted to research ways to keep meteoroids from making holes in spacecrafts. Thick walls may help. Or perhaps spacecrafts can be covered with a metal skin that will seal itself.$t$,
            137)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Where do the meteoroids originate?$t$,
          jsonb_build_array($t$from the outer layer of the earth$t$, $t$from the other planets$t$, $t$from the outer space$t$, $t$from the moon$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$A meteoroid catches fire when$t$,
          jsonb_build_array($t$it hits the earth.$t$, $t$it falls to the ground.$t$, $t$it collides with a spacecraft.$t$, $t$it comes into the air near the earth.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$When is a meteoroid dangerous?$t$,
          jsonb_build_array($t$when it falls to earth and burns down houses$t$, $t$when it makes holes in a spacecraft$t$, $t$when it hits the airplanes$t$, $t$when it catches fire$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$The rocks from outer space are studied to find out ________________.$t$,
          jsonb_build_array($t$the time that they fall on earth.$t$, $t$how these rocks could be used$t$, $t$how to avoid their fall on earth$t$, $t$how to keep them from making holes in spacecraft$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$What is true of meteoroids, meteorites, and meteors?$t$,
          jsonb_build_array($t$They are all small.$t$, $t$They are all rocks.$t$, $t$They all fall to the earth.$t$, $t$They all turn into balls of fire.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$When one sees a flash of light in space, he may exclaim _____________.$t$,
          jsonb_build_array($t$"That's a meteor."$t$, $t$"There's a meteorite."$t$, $t$"That's a meteoroid."$t$, $t$"A meteoroid hit a spacecraft."$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$Which is the best definition of a meteorite?$t$,
          jsonb_build_array($t$a flash of light from a burning meteoroid$t$, $t$a piece of meteoroid that falls to the ground$t$, $t$a piece of rock from outer space that hit a spacecraft$t$, $t$a piece of rock from outer space that burn up before hitting the ground$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$In the sentence, "They research ways to keep meteoroids from making holes in the spacecraft," another word for research is ____________.$t$,
          jsonb_build_array($t$study$t$, $t$solve$t$, $t$conclude$t$, $t$experiment$t$), 'a')
  on conflict (passage_id, question_no) do nothing;

  -- post Set A, level 7: Diving (163 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'post' and set_code = 'A' and level = 7;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', 'A', 7, $t$Diving$t$,
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

  -- post Set B, level 2: Bam and Tagpi (35 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'post' and set_code = 'B' and level = 2;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', 'B', 2, $t$Bam and Tagpi$t$,
            $t$Do you have a pet dog? What do you do with your pet dog?
In the story, let's find out: Who has a pet dog? What does he do with his pet dog?$t$,
            $t$Bam is sad. "Where is Tagpi?" Where is my pet dog? I want to play with him. He is not in the room."
"Aw! Aw!" "Where are you, Tagpi? Oh, you are in the garden."$t$,
            35)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Who is Tagpi?$t$,
          jsonb_build_array($t$the pet dog of Bam$t$, $t$the brother of Bam$t$, $t$the classmate of Bam$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$Where did Bam first look for Tagpi?$t$,
          jsonb_build_array($t$in the room$t$, $t$in the kitchen$t$, $t$in the garden$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Why did Bam look for Tagpi?$t$,
          jsonb_build_array($t$He wants to feed Tagpi.$t$, $t$He wants to play with Tagpi.$t$, $t$He wants to give Tagpi a bath.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Where did Bam find Tagpi?$t$,
          jsonb_build_array($t$in the hut$t$, $t$in the garden$t$, $t$under the bed$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$What did Bam feel when he found Tagpi?$t$,
          jsonb_build_array($t$sad$t$, $t$mad$t$, $t$glad$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- post Set B, level 3: The Caps and the Kittens (58 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'post' and set_code = 'B' and level = 3;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', 'B', 3, $t$The Caps and the Kittens$t$,
            $t$What do you use a cap for?
In the story, let's find out: What do the kittens use the cap for?$t$,
            $t$Dan and Pepe will play. "But the sun is hot," says Pepe. "Let us get our caps," says Dan. "My cap is not on my bed," says Pepe. "My cap is not in my bag," says Dan. "Look boys! Our cat has kittens," says Mama. "Mik-mik has four kittens!" says Dan. "Yay! The kittens nap in our caps!"$t$,
            58)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Why did Dan and Pepe need their caps?$t$,
          jsonb_build_array($t$The sun is hot.$t$, $t$They will play with their caps.$t$, $t$They will give the caps to the kittens.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What did Mama want them to look at?$t$,
          jsonb_build_array($t$the bag$t$, $t$the bed$t$, $t$the kittens$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Who is Mik-mik?$t$,
          jsonb_build_array($t$the pet cat$t$, $t$the fat kitten$t$, $t$the big dog$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$What did the kittens use the caps for?$t$,
          jsonb_build_array($t$for playing$t$, $t$for sleeping on$t$, $t$for keeping them free from the hot sun$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$What did the boys feel when they saw the kittens?$t$,
          jsonb_build_array($t$sad$t$, $t$mad$t$, $t$happy$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$What do you think will the boys do after?$t$,
          jsonb_build_array($t$The boys will send the kittens away.$t$, $t$The boys will take the caps from the kittens.$t$, $t$The boys will let the kittens sleep on their caps.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- post Set B, level 4: Cat and Mouse (80 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'post' and set_code = 'B' and level = 4;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', 'B', 4, $t$Cat and Mouse$t$,
            $t$What do you know about a cat? What do you know about a mouse?
In the story, let's find out the characteristics of the cat and the mouse.$t$,
            $t$A mouse and a cat lived in an old house. The mouse stayed in a hole while the cat slept under the table.
One night, the mouse got out of its hole. "Mmm, Cheese!" it thought, as it went up the table. As it started nibbling the cheese, a fork fell. It woke the cat up so it ran up the table. But the mouse was too fast for the cat. It quickly dashed to its hole. Safe at last!$t$,
            80)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Where did the cat and the mouse live?$t$,
          jsonb_build_array($t$in a big hole$t$, $t$in an old house$t$, $t$under the dining table$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$Why did the mouse get out of its hole?$t$,
          jsonb_build_array($t$to find a mate$t$, $t$to look for food$t$, $t$to play with the cat$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Why did the cat wake up?$t$,
          jsonb_build_array($t$It smelled the food.$t$, $t$The mouse asked it to play.$t$, $t$It heard the noise made by the fork.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$In order to catch the mouse, what could the cat do next time?$t$,
          jsonb_build_array($t$run faster$t$, $t$sleep later$t$, $t$stay alert for loud sounds$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Which happened last in the story?$t$,
          jsonb_build_array($t$The mouse smelled the food on the table.$t$, $t$The cat woke up and chased the mouse.$t$, $t$The mouse ran to its hole.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Why was the mouse thankful at the end of the story?$t$,
          jsonb_build_array($t$It was able to get away from the cat.$t$, $t$It ate bread and cheese.$t$, $t$It saw the cat.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;

  -- post Set B, level 5: The Great Runner (94 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'post' and set_code = 'B' and level = 5;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', 'B', 5, $t$The Great Runner$t$,
            $t$Are you a great runner? Who can beat you in a race?
In the selection that you will read, find out: Who is a great runner? Who beat her in a race?$t$,
            $t$Atalanta is a lovely princess and a great runner. One day, her father told her, "It's time you get married." "I will marry a man who will beat me in a race," replied Atalanta. Many young men tried their luck. But they all lost. Hippomenes asked the goddess of love for help. "Here are three golden apples," she said. "During the race, throw one apple in front of Atalanta. She will stop to pick it up. That should slow her down." Hippomenes heeded her advice and won the race. Thus, Atalanta became his wife.$t$,
            94)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Which sentence says something about Atalanta?$t$,
          jsonb_build_array($t$She did not want to get married.$t$, $t$She was an obedient daughter.$t$, $t$She was a great runner.$t$, $t$She loved Hippomenes.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What kind of man would she marry?$t$,
          jsonb_build_array($t$a kind prince$t$, $t$a clever ruler$t$, $t$a great runner$t$, $t$a handsome man$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Hippomenes became Atalanta's __________________.$t$,
          jsonb_build_array($t$friend$t$, $t$enemy$t$, $t$adviser$t$, $t$husband$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Many tried their luck. When one tries his luck, he ___________$t$,
          jsonb_build_array($t$always wins.$t$, $t$is sure to win.$t$, $t$really wants to win.$t$, $t$attempts to win.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Hippomenes heeded Aphrodite's advice. The synonym of heeded is$t$,
          jsonb_build_array($t$followed$t$, $t$disobeyed$t$, $t$laughed at$t$, $t$disregarded$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Who was Aphrodite?$t$,
          jsonb_build_array($t$the godmother of Hippomenes$t$, $t$the mother of Atalanta$t$, $t$the goddess of love$t$, $t$the great teacher$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$How did the golden apples help Hippomenes win?$t$,
          jsonb_build_array($t$They had magic powers.$t$, $t$They made Atalanta sleepy.$t$, $t$They delayed Atalanta during the race.$t$, $t$They gave Hippomenes strength in running.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- post Set B, level 6: Beetles (140 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'post' and set_code = 'B' and level = 6;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', 'B', 6, $t$Beetles$t$,
            $t$Where do you find beetles?
In the selection, find out: Where are beetles found? Why do they survive anywhere?$t$,
            $t$Beetles can adapt to any kind of environment. They can be found crawling, burrowing, flying, and swimming on every part of the earth except the ocean. Why do beetles survive well on our planet? First, they have tough compact bodies. These help them hide, find food, and lay eggs in places where other insects could never go.
Almost all beetles have tough front wings which are colorful and carry beautiful patterns. These wings also act as suit of armor to protect the beetles' transparent hind wings which are used for flying.
Beetles have mouth parts designed for chewing different food. They eat other insects, animal dung, and even cloth. They also feed on the bark, leaves, flowers, and fruits of any kind of plant. They can even chew around the stems of poisonous plants to let the deadly sap drain.$t$,
            140)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$In which of these places WON'T you find beetles?$t$,
          jsonb_build_array($t$in the mountain$t$, $t$in the plains$t$, $t$in the sea$t$, $t$in the hill$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$In the sentence Beetles can adapt to any kind of environment, which is a synonym of adapt?$t$,
          jsonb_build_array($t$get used to$t$, $t$change$t$, $t$crawl$t$, $t$eat$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$What pair of words describe the beetles' front wings?$t$,
          jsonb_build_array($t$transparent and thick$t$, $t$tough and colorful$t$, $t$wide and thick$t$, $t$silky and soft$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$What is the use of the beetles' hind wings?$t$,
          jsonb_build_array($t$for protecting the front wings$t$, $t$for covering the body$t$, $t$for finding food$t$, $t$for flying$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Which of the following states the main idea of this selection?$t$,
          jsonb_build_array($t$reasons why beetles can survive anywhere$t$, $t$places where one can find beetles$t$, $t$the compact body of the beetles$t$, $t$the food that beetles eat$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$What action of the beetle means making a hole in the ground?$t$,
          jsonb_build_array($t$burrowing$t$, $t$swimming$t$, $t$crawling$t$, $t$flying$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$The front wings of most beetles ______________.$t$,
          jsonb_build_array($t$are transparent$t$, $t$hide the beetles$t$, $t$protect the hind wings$t$, $t$maybe used for swimming$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$If someone says, "You eat like a beetle" it means that _____________.$t$,
          jsonb_build_array($t$You are a picky eater.$t$, $t$You can eat anything.$t$, $t$You don't have appetite.$t$, $t$You eat very little amount of food.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;

  -- post Set B, level 7: The Brain (160 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'post' and set_code = 'B' and level = 7;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', 'B', 7, $t$The Brain$t$,
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

  -- post Set C, level 2: Pets (33 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'post' and set_code = 'C' and level = 2;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', 'C', 2, $t$Pets$t$,
            $t$Do you have a pet?
What is your pet?$t$,
            $t$I am Pat. I have a pet cat.
I am Ben. I have a pet hen.
I am Mig. I have a pet pig.
I am Det. I too will have a pet.$t$,
            33)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$What is Pat's pet?$t$,
          jsonb_build_array($t$pig$t$, $t$cat$t$, $t$hen$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$Who has a pet pig?$t$,
          jsonb_build_array($t$Mig$t$, $t$Pat$t$, $t$Ben$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$How many children have pets?$t$,
          jsonb_build_array($t$two$t$, $t$four$t$, $t$three$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Who has a pet that can lay eggs?$t$,
          jsonb_build_array($t$Mig$t$, $t$Ben$t$, $t$Det$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$What is the message of the story?$t$,
          jsonb_build_array($t$People can have three pets.$t$, $t$People can have the same pet.$t$, $t$People can have different pets.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- post Set C, level 3: A Happy Place (55 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'post' and set_code = 'C' and level = 3;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', 'C', 3, $t$A Happy Place$t$,
            $t$What do you consider to be a happy place?
In this story, what does Dan consider to be a happy place?$t$,
            $t$"Come with me," says Dan. "Where will we go?" Mina asks.
"We will go to a happy place that has lots of balloons."
"We will play, dance, and run. We will have so much fun. We will eat orange cake that our mom and dad baked."
"And then we will sing,
Happy birthday, dear Benny!"$t$,
            55)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Who asked Mina to go to a happy place?$t$,
          jsonb_build_array($t$Mom$t$, $t$Dan$t$, $t$Dad$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What word says something about the happy place?$t$,
          jsonb_build_array($t$quiet$t$, $t$noisy$t$, $t$far$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$What will the children do in the happy place?$t$,
          jsonb_build_array($t$They will sing, skip and hop.$t$, $t$They will read, write and count.$t$, $t$They will dance, run and play.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Whose birthday is it?$t$,
          jsonb_build_array($t$Dan$t$, $t$Mina$t$, $t$Benny$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Which word tells what Dan feels?$t$,
          jsonb_build_array($t$sad$t$, $t$afraid$t$, $t$excited$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$What is the best response that Benny can make after seeing Dan and Mina?$t$,
          jsonb_build_array($t$I'm glad you came.$t$, $t$I can't wait to go home.$t$, $t$I want to sing with you.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;

  -- post Set C, level 4: Marian's Experiment (80 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'post' and set_code = 'C' and level = 4;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', 'C', 4, $t$Marian's Experiment$t$,
            $t$What science experiment have you done?
In this selection, what was Marian's experiment?$t$,
            $t$Marian came home from school. She went to the kitchen and saw her mother cooking.
"Mama, do we have mongo seeds?" asked Marian. "I will do an experiment."
"Yes, we have some in the cabinet," answered Mama. Marian got some seeds and planted them in a wooden box. She watered the seeds every day. She made sure they got enough sun. After three days, Marian was happy to see stems and leaves sprouting. Her mongo seeds grew into young plants.$t$,
            80)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$What did Marian look for in the kitchen?$t$,
          jsonb_build_array($t$mango seeds$t$, $t$mongo seeds$t$, $t$melon seeds$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What did she do with the seeds?$t$,
          jsonb_build_array($t$She played with them.$t$, $t$She cooked them.$t$, $t$She planted them.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Which of the following events happened last?$t$,
          jsonb_build_array($t$Some stems and leaves sprouted from the seeds.$t$, $t$Marian planted the mongo seeds in a wooden box.$t$, $t$Marian watered the soil where the seeds were planted.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$What did Marian know about planting seeds?$t$,
          jsonb_build_array($t$Seeds should be placed in a wooden box in the house.$t$, $t$Seeds grow whether or not one takes care of them.$t$, $t$Seeds need water and sunlight in order to grow.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$What can one learn from Marian?$t$,
          jsonb_build_array($t$It is good to be happy.$t$, $t$It is good to be curious.$t$, $t$It is good to be obedient.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Which sentence tells that Marian's experiment was successful?$t$,
          jsonb_build_array($t$Mother said there were mongo seeds in the cabinet.$t$, $t$Stems and leaves started to sprout from the seeds.$t$, $t$The mongo seeds had enough water and sunlight.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;

  -- post Set C, level 5: Trading Places (99 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'post' and set_code = 'C' and level = 5;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', 'C', 5, $t$Trading Places$t$,
            $t$Have you ever pretended to be someone else?
In this selection, find out what the main character pretended to be.$t$,
            $t$On a trip to a university, the driver told the professor, "I've heard you give this speech many times. I can deliver it for you."
The professor said, "The people in this university haven't seen me yet. Give the lecture. I'll pretend to be your driver."
When they arrived, the driver was introduced to be the professor. He gave an excellent speech. Everybody applauded. Afterwards, somebody asked a question which the driver could't answer. In order to get out of the sticky situation, he said, "Oh, that's such an easy question. Even my driver can give you the answer!"$t$,
            99)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Why did the university invite the professor?$t$,
          jsonb_build_array($t$to give a test$t$, $t$to give a lecture$t$, $t$to donate books$t$, $t$to attend classes$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$Why was it easy for the driver to pretend he was the professor?$t$,
          jsonb_build_array($t$The professor looked like the driver.$t$, $t$The driver dressed up like the professor.$t$, $t$The driver was as intelligent as the professor.$t$, $t$The participants have not seen the professor yet.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Why was the selection entitled Trading Places?$t$,
          jsonb_build_array($t$The driver could answer the question asked.$t$, $t$The professor exchanged roles with the driver.$t$, $t$The driver exchanged seats with the professor.$t$, $t$The professor seated himself with the audience.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Based on the selection, how would you describe the professor?$t$,
          jsonb_build_array($t$a boring lecturer$t$, $t$an excellent driver$t$, $t$a humorous person$t$, $t$a generous employer$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$The driver tried to get out of a sticky situation.
What was the sticky situation?$t$,
          jsonb_build_array($t$A participant recognized the professor.$t$, $t$The driver could not deliver the lecture.$t$, $t$The professor could not move from his seat.$t$, $t$The driver did not know what to answer.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Why did the driver say "Even my driver can give you the answer!"?$t$,
          jsonb_build_array($t$to admit that even he did not know how to answer$t$, $t$to stop the audience from asking more questions$t$, $t$to stop the real professor from answering the question$t$, $t$to prove to the participants that the question was easy$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$He gave a very good speech and everybody applauded.
Another word for applauded is ________________________.$t$,
          jsonb_build_array($t$kept very quiet$t$, $t$started to leave$t$, $t$clapped their hands$t$, $t$asked him to speak louder$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- post Set C, level 6: Just How Fast (141 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'post' and set_code = 'C' and level = 6;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', 'C', 6, $t$Just How Fast$t$,
            $t$How fast can you move?
In the selection, find out just how different things can move$t$,
            $t$Many things around us move at different rates. Glaciers, which are frozen rivers of snow, move less than one foot in a day. A box turtle travels about ten feet per minute, while a snail travels five inches per hour. A chimney swift flies almost ninety miles per hour. This is the fastest speed recorded for any living creature.
A hydroplane skims across the top of the water at nearly 300 miles an hour. Some racing cars travel more than 500 miles per hour. The wind in a tornado may move at 600 miles per hour but sound waves are faster with a speed of up to 740 miles per hour.
The Earth moves around the sun at 67,000 miles per hour. At 186,000 miles per second, light is faster! Science has yet to discover anything that would surpass this speed.$t$,
            141)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Which living creature has the highest recorded speed?$t$,
          jsonb_build_array($t$a box turtle$t$, $t$light waves$t$, $t$sound waves$t$, $t$a chimney swift$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$Among the following, which has the slowest rate of movement?$t$,
          jsonb_build_array($t$a snail$t$, $t$a glacier$t$, $t$a box turtle$t$, $t$a chimney swift$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$What does this statement mean? "Science has yet to discover anything that would surpass the speed of light."$t$,
          jsonb_build_array($t$Someday, something faster than light will be discovered.$t$, $t$Of all moving objects, only light waves will never slow down.$t$, $t$Among all things, light waves will always have the fastest speed.$t$, $t$Of all that has been observed, light waves have the fastest speed.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Which among these statements is true?$t$,
          jsonb_build_array($t$A box turtle is faster than a snail.$t$, $t$A snail is faster than a box turtle.$t$, $t$A hydroplane is slower than a glacier.$t$, $t$A glacier is faster than a hydroplane.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Which among these statements is NOT supported by the selection?$t$,
          jsonb_build_array($t$Tornadoes are around double the speed of a hydroplane.$t$, $t$Sound waves are about two times the speed of light waves.$t$, $t$A hydroplane is about half the speed of the wind in a tornado.$t$, $t$The speed of light is faster than the speed of the earth's rotation.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$"Science has yet to discover anything that would surpass this speed." The synonym of surpass is ____________.$t$,
          jsonb_build_array($t$equal$t$, $t$reduce$t$, $t$accede$t$, $t$exceed$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$Which among these statements is an opinion?$t$,
          jsonb_build_array($t$Sound waves move faster than the wind.$t$, $t$There will never be anything faster than light.$t$, $t$Many things differ in their rates of movement.$t$, $t$The earth orbits the sun at 67,000 miles per hour.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$Which sentence states the main idea of the selection?$t$,
          jsonb_build_array($t$A hydroplane skims across the top of the water at nearly 300 miles an hour.$t$, $t$There are many things found around us that move at different rates.$t$, $t$The chimney swift has the fastest recorded speed among living things.$t$, $t$The Earth orbits the sun at 67,000 miles per hour but light moves faster.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;

  -- post Set C, level 7: Air Currents (153 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'post' and set_code = 'C' and level = 7;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', 'C', 7, $t$Air Currents$t$,
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
  -- CHECK: Q3 asks for an ANTONYM of frigid but the printed key is B (very cold, a synonym); C (very hot) looks intended. Kept as printed.
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Siberia is a very frigid place. What is an antonym for the word frigid?$t$,
          jsonb_build_array($t$very moist$t$, $t$very cold$t$, $t$very hot$t$, $t$very windy$t$), 'b')
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
          jsonb_build_array($t$examples$t$, $t$cause and effect$t$, $t$a series of events$t$, $t$problem and solution$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$Which could be another title of the selection?$t$,
          jsonb_build_array($t$Different Causes of Heavy Rains$t$, $t$How Air Streams Affect Climate$t$, $t$Northwest and Southwest Monsoons$t$, $t$Hot and Cold Temperature in the Country$t$), 'b')
  on conflict (passage_id, question_no) do nothing;

  -- post Set D, level 2: Where the Pets Sat (37 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'post' and set_code = 'D' and level = 2;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', 'D', 2, $t$Where the Pets Sat$t$,
            $t$Where do you often sit?
Where did the pets sit?$t$,
            $t$Mat is a cat. Mat sat on a hat.
Jig is a pig. Jig sat on a wig.
Len is a hen. Len did not sit on a hat or a wig.
Len sat on ten eggs!$t$,
            37)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Where did the pig sit?$t$,
          jsonb_build_array($t$on a hat$t$, $t$on a wig$t$, $t$on ten eggs$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What did the cat do?$t$,
          jsonb_build_array($t$sat on eggs$t$, $t$sat on a wig$t$, $t$sat on a hat$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Which animal sits on something that can break?$t$,
          jsonb_build_array($t$the hen$t$, $t$the cat$t$, $t$the pig$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Why was it good for Len to sit on the eggs?$t$,
          jsonb_build_array($t$so the eggs will not get lost$t$, $t$so the eggs will hatch into chicks$t$, $t$so the eggs will stay on the nest$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Which of the following will happen last?$t$,
          jsonb_build_array($t$The hen will lay eggs.$t$, $t$The hen will sit on the eggs.$t$, $t$The hen will have chicks.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- post Set D, level 3: In the Park (58 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'post' and set_code = 'D' and level = 3;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', 'D', 3, $t$In the Park$t$,
            $t$What do you like to do in the park?
What do the children like to do in the park?$t$,
            $t$Today, Sam and Ria will go to the park. What will they do there?
They will sit on the grass and look at some bugs.
They will look at the holes that the worms have just dug.
That is where they will stay on this warm summer day.
But they must leave the park before it gets dark.$t$,
            58)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Who will go to the park?$t$,
          jsonb_build_array($t$Cam and Mia$t$, $t$Dan and Iya$t$, $t$Sam and Ria$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What will the children do in the park?$t$,
          jsonb_build_array($t$play with other children$t$, $t$observe the insects$t$, $t$watch the clouds$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Why are the children not in school?$t$,
          jsonb_build_array($t$It is their Christmas break.$t$, $t$They are on a class field trip.$t$, $t$It is their summer vacation.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$When should the children leave the park?$t$,
          jsonb_build_array($t$night time$t$, $t$lunch time$t$, $t$late afternoon$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$What else can the two children do at the park?$t$,
          jsonb_build_array($t$play with others$t$, $t$watch the stars$t$, $t$eat their dinner$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$What is the message of the story?$t$,
          jsonb_build_array($t$There are children who do not like the park.$t$, $t$There are people who tell others to visit the park.$t$, $t$There are many things to see and do at the park.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- post Set D, level 4: On Market Day (80 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'post' and set_code = 'D' and level = 4;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', 'D', 4, $t$On Market Day$t$,
            $t$Where do you go with your parents every Saturday?
Where did Manuel go with his father on Saturday?$t$,
            $t$Every Saturday, Manuel goes to market with his father, Mang Ador. They always pass by Aling Juaning's stall to buy meat. They go to Mang Tinoy's for fresh vegetables. They also visit Aling Tita's seafood section.
Whenever Mang Ador buys something, Manuel always tries to predict what his father will cook for lunch. Today Mang Ador bought tamarind, tomatoes, string beans, radish, and shrimp.
"I know what we will have for lunch," says Manuel happily. Can you guess it, too?$t$,
            80)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$Who is the father in the selection?$t$,
          jsonb_build_array($t$Ador$t$, $t$Tinoy$t$, $t$Manuel$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$Which stall do the father and son get their fish from?$t$,
          jsonb_build_array($t$Mang Tinoy's stall$t$, $t$Aling Tita's stall$t$, $t$Aling Juaning's stall$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$What section of the market do the father and son always go to?$t$,
          jsonb_build_array($t$fish, meat, and fruits sections$t$, $t$vegetable, fish, and fruit sections$t$, $t$vegetable, seafood, and meat sections$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$In the story, the boy tries to predict what they will have for lunch.
When one tries to predict, one tries to ______.$t$,
          jsonb_build_array($t$ask$t$, $t$hear$t$, $t$guess$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$The boy in the story shows us that a person can find out what his family will have for lunch by ______________.$t$,
          jsonb_build_array($t$looking at what his father buys from the market$t$, $t$asking his mother what she thinks his father will cook$t$, $t$smelling the scents in the kitchen as his father cooks$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$What do you think does Manuel say on their way to the market?$t$,
          jsonb_build_array($t$"I'm tired."$t$, $t$"I'm excited."$t$, $t$"I'm nervous."$t$), 'b')
  on conflict (passage_id, question_no) do nothing;

  -- post Set D, level 5: The Legend of the Firefly (100 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'post' and set_code = 'D' and level = 5;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', 'D', 5, $t$The Legend of the Firefly$t$,
            $t$What are you most afraid of?
What are the stars most afraid of?$t$,
            $t$There was a time when young and old stars could talk to Bathala. One day, the young stars learned that they become part of a black hole when they grow old. The young stars feared losing their light. They asked Bathala for help.
"I have a solution. But you have to give up a lot," said Bathala. "You need to leave the heavens and live on land." Some of the younger stars agreed.
On a dark night, you might chance upon these stars. They have turned into tiny twinkling bugs whose tails flicker as they fly from place to place.$t$,
            100)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$What did the younger stars fear?$t$,
          jsonb_build_array($t$asking for help$t$, $t$becoming insects$t$, $t$losing their light$t$, $t$leaving the heavens$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What was Bathala's solution to the younger stars' problem?$t$,
          jsonb_build_array($t$He will make them young forever.$t$, $t$He will turn them into bugs with lights.$t$, $t$He will give them their light for eternity.$t$, $t$He will give them a new life in the heavens.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$"One might chance upon these stars on a very dark night." Which statement below means the same thing?$t$,
          jsonb_build_array($t$One will always see these stars on a very dark night.$t$, $t$One will never see the stars on a very dark night.$t$, $t$One will surely see these stars on a very dark night.$t$, $t$One will possibly see these stars on a very dark night.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$The story is a legend. This means that _________________.$t$,
          jsonb_build_array($t$It is a real story about a person's life.$t$, $t$It is a story which could really happen.$t$, $t$It is a story about where things came from.$t$, $t$It is a story where there are talking animals.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$According to the selection, what is a firefly?$t$,
          jsonb_build_array($t$a bug that wants so much to be a star$t$, $t$an old star that already lost its energy$t$, $t$an insect that died and went to heaven$t$, $t$a young star that became a glowing insect$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Which statement is NOT explicitly stated in the given selection?
Fireflies are _____________________.$t$,
          jsonb_build_array($t$young stars that did not want to lose their energy$t$, $t$twinkling bugs that used to be fearful young stars$t$, $t$insects with chemicals that make their bodies glow$t$, $t$young stars that once lived in the heavens with old stars$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$Why did Bathala say "you would have to give up much" to the young stars?$t$,
          jsonb_build_array($t$Life on earth will give them less light.$t$, $t$The young stars will give up their lives.$t$, $t$The young stars will not be happy on earth.$t$, $t$Life was better in the heavens than on earth.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;

  -- post Set D, level 6: Flying Rocks (139 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'post' and set_code = 'D' and level = 6;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', 'D', 6, $t$Flying Rocks$t$,
            $t$What can be found in the solar system?
In this selection, find out what other things can be found in the solar system.$t$,
            $t$There are rocks in our Solar System that never flocked together to form planets. Larger ones called asteroids gather in the Asteroid Belt, a strip found between Mars and Jupiter. Some asteroids don't move along this belt but have paths that bring them close to the earth. These are called Apollo Asteroids.
There may be half a million asteroids whose diameters are bigger than one kilometer. The largest asteroid is over 1000 kilometers across. It is speculated that many asteroids were once larger but they collided with each other and became small fragments.
Unlike asteroids, meteoroids are small rocky bodies, that are scattered in space and do not orbit the sun. They cross the Earth's orbit and are often seen burning up in the Earth's atmosphere at night. The faint flashes of light they make are called shooting stars.$t$,
            139)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$What are asteroids?$t$,
          jsonb_build_array($t$Large fragments of rock in the Solar System$t$, $t$Large fragments of rock that circle the moon$t$, $t$Small fragments of rock that do not circle the sun$t$, $t$Small fragments of rock that do not circle the planets$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, null, $t$What are meteoroids?$t$,
          jsonb_build_array($t$Large fragments of rock that circle the sun$t$, $t$Large fragments of rock that circle the planets$t$, $t$Small bits of rock that do not circle the sun$t$, $t$Small bits of rock that do not cross the planets' orbits$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, null, $t$Which among the following statements is NOT true?$t$,
          jsonb_build_array($t$Some asteroids move close to the earth.$t$, $t$Large rocks flock together in the Asteroid Belt.$t$, $t$All rocks in our Solar System have formed planets.$t$, $t$The Asteroid Belt is found between Mars and Jupiter.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$"It is speculated that many asteroids were once larger." What does the word speculated mean?$t$,
          jsonb_build_array($t$written$t$, $t$guessed$t$, $t$confirmed$t$, $t$questioned$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$What is a possible reason behind the fact that asteroids are not anymore as large as they were first thought to be?$t$,
          jsonb_build_array($t$They could have shrunk when they got closer to the sun.$t$, $t$They could have hit one another and broken into pieces.$t$, $t$They could have burned up and eventually become smaller.$t$, $t$They could have rammed into some planet and broken apart.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Which of the following statements is TRUE of asteroids and meteoroids?$t$,
          jsonb_build_array($t$Both asteroids and meteoroids can be seen in a belt of rocks between Jupiter and Mars.$t$, $t$Both asteroids and meteoroids circle the Earth and can be seen as faint flashes of light.$t$, $t$Both asteroids and meteoroids are composed of rocky particles found in the Solar System.$t$, $t$Both asteroids and meteoroids are scattered randomly across in space and do not orbit the sun.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$Many asteroids must have collided with one another. What is a synonym of the word "collided?"$t$,
          jsonb_build_array($t$trapped into$t$, $t$crashed into$t$, $t$converged with$t$, $t$connected with$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$If you see faint flashes of light in the night sky, which of the following could have happened?$t$,
          jsonb_build_array($t$Flames shoot up from the sun and come closer to the earth.$t$, $t$Meteoroids have just crossed the earth's orbit and burned up.$t$, $t$Meteoroids have just crossed paths with the sun and burned up.$t$, $t$There are moments when the earth orbits a lot closer to the sun.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;

  -- post Set D, level 7: Ecosystems (160 words)
  select id into p from public.phil_iri_passages
   where collection_id = c and test_type = 'post' and set_code = 'D' and level = 7;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', 'D', 7, $t$Ecosystems$t$,
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
  -- CHECK: Q7 refers to a food-chain diagram that is only in the printed manual; the learner cannot answer it from the text alone.
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$The diagram below shows an ocean ecosystem. The arrows point to the food source of the succeeding organism. If a new organism is introduced into the system and it eats the shrimplike creatures, how will this indirectly affect the mackerel?$t$,
          jsonb_build_array($t$The mackerel will have no more shrimplike creatures to eat.$t$, $t$The mackerel will still be eaten by the tuna fish as it continues to consume the small fish.$t$, $t$The mackerel will be eaten by the small fish which now has to look for a new food source.$t$, $t$The mackerel might lose its food since without a food source, the small fish could die.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  -- CHECK: Q8 same diagram as Q7 (printed as a second "7.", numbered 8 here).
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$Using the same diagram, which of the following statements is FALSE?$t$,
          jsonb_build_array($t$The small fish depends solely on shrimplike creatures for food.$t$, $t$The tuna fish depends solely on the mackerel as its food source.$t$, $t$The large shark depends solely on the tuna fish as its food source.$t$, $t$The shrimplike creatures depend solely on one-celled life for food.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
end
$seed$;

-- Check (read-only): 47 passages (23 pre, 24 post), 314 questions in all,
-- 5/6/6/7/8/8 questions for levels 2-7, word counts as noted above.
-- select p.test_type, p.set_code, p.level, p.title, p.word_count, count(q.id) as questions
--   from public.phil_iri_passages p
--   join public.phil_iri_collections c on c.id = p.collection_id
--   left join public.phil_iri_questions q on q.passage_id = p.id
--  where c.school_id is null and c.name = 'Phil-IRI 2018'
--  group by p.id order by p.test_type desc, p.set_code, p.level;
