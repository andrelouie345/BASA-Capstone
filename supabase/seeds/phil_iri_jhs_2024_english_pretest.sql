-- Phil-IRI for JHS (2024), English pretest graded passages, Grades 4-10.
-- Source: Phil-IRI Manuals 2018 & 2024, "Teacher's Copy" of the pretest graded
-- passages and its Key to Correction (pp. 73-91 of the JHS part).
--
-- One region-wide, prescribed collection "Phil-IRI JHS 2024" (counted in DepEd
-- reports), one passage per grade, multiple-choice questions with the printed key.
--
-- Idempotent: run it in the SQL Editor (cloud) or on the LAN instance as often as
-- needed. Existing rows are left alone (a passage that has been read is locked
-- anyway); to correct a passage, edit it through the app or console.
--
-- Text: paragraph markers like "[1]" are left out (they are not read aloud);
-- paragraphs are separated by a newline; words broken across lines are rejoined.
--
-- Word counts: word_count is the number of words in the text as stored, which is
-- what miscue taps and the word bound use (PhilIriPassage.words). The manual
-- prints no count for Grades 4-6 and inconsistent ones for 7-10 (Grade 8 matches;
-- Grades 7 and 10 match only with the title's words added; Grade 9 matches
-- neither way). Printed counts are noted next to each passage.
--
-- Question types (literal/inferential/critical) are not given for the graded
-- passages, so question_type stays null.
--
-- Contains nothing that bypasses RLS: created_by stays null when run without a
-- signed-in user (SQL Editor), as the stamp trigger allows.

do $seed$
declare
  c bigint;
  p bigint;
begin
  select id into c from public.phil_iri_collections
   where school_id is null and lower(name) = lower('Phil-IRI JHS 2024');
  if c is null then
    insert into public.phil_iri_collections
      (school_id, name, description, is_prescribed, is_grade_leveled, has_comprehension)
    values (null, 'Phil-IRI JHS 2024',
            'Phil-IRI for Junior High School (DepEd, 2024): graded passages for Grades 4-10.',
            true, true, true)
    returning id into c;
  end if;

  -- Grade 4: Anansi's Web (86 words; not printed)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 4 and test_type = 'pre' and title = $t$Anansi's Web$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', null, 4, $t$Anansi's Web$t$,
            $t$Why does a spider make itself a web?
In the story, let's find out why a spider makes a web.$t$,
            $t$Anansi was tired of her web. So, one day, she said "I will go live with the ant."
Now, the ant lived in a small hill. Once in the hill Anansi cried, "This place is too dark! I will go live with the bees."
When she got to the beehive, Anansi cried, "This place is too hot and sticky! I will go live with the beetle."
But on her way to beetle's home, she saw her web. "Maybe a web is the best place after all."$t$,
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

  -- Grade 5: Amy's Good Deed (106 words; not printed)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 5 and test_type = 'pre' and title = $t$Amy's Good Deed$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', null, 5, $t$Amy's Good Deed$t$,
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
  values (p, 6, null, $t$What for Amy is a "good deed"?$t$,
          jsonb_build_array($t$a surprise$t$, $t$a harmful act$t$, $t$a brave action$t$, $t$an act of kindness$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$Which phrase best describes Amy?$t$,
          jsonb_build_array($t$a hardworking girl$t$, $t$a brave pet owner$t$, $t$a caring person$t$, $t$a diligent student$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- Grade 6: Dreams (141 words; not printed)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 6 and test_type = 'pre' and title = $t$Dreams$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'pre', null, 6, $t$Dreams$t$,
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
  values (p, 7, null, $t$In the selection, what does it mean to "sleep on it?"$t$,
          jsonb_build_array($t$ignore it$t$, $t$take a nap$t$, $t$think about it$t$, $t$forget about it$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$Which could be a good title for this selection?$t$,
          jsonb_build_array($t$Dreaming: Explained$t$, $t$Preventing Our Dreams$t$, $t$Interpreting One's Dream$t$, $t$Finding Solutions to Dreaming$t$), 'a')
  on conflict (passage_id, question_no) do nothing;

  -- Grade 7: Lili the Lizard and Koko the Gecko (357 words; printed 364)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 7 and test_type = 'pre' and title = $t$Lili the Lizard and Koko the Gecko$t$;
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
          jsonb_build_array($t$to spend according to one's budget$t$, $t$to spend according to one's limit$t$, $t$to spend according to one's needs$t$, $t$to spend according to one's wants$t$), 'a')
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

  -- Grade 8: The Amazing World of Coral Reefs (303 words; printed 303)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 8 and test_type = 'pre' and title = $t$The Amazing World of Coral Reefs$t$;
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
  -- CHECK: Q1 printed key is A (algae); the passage says reefs are built by coral polyps from calcium carbonate, so C or D looks intended. Kept as printed.
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, null, $t$What are coral reefs made of?$t$,
          jsonb_build_array($t$algae$t$, $t$anemones$t$, $t$calcium$t$, $t$polyps$t$), 'a')
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
          jsonb_build_array($t$death of coral reefs and other marine life$t$, $t$erosion of coast lines and storm surges$t$, $t$loss of vibrant colors of the coral reefs$t$, $t$warmer ocean temperatures and acidity$t$), 'b')
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
          jsonb_build_array($t$I and II$t$, $t$I and III$t$, $t$II, and IV$t$, $t$I and IV$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 9, null, $t$Which of the following best describes the last paragraph?$t$,
          jsonb_build_array($t$It is didactic, that is, it intended to teach.$t$, $t$It contains the main topic of the selection.$t$, $t$It has a very serious and formal tone.$t$, $t$It provides support to the ideas presented.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 10, null, $t$Which of the following is true about this article?$t$,
          jsonb_build_array($t$It appeals to environmentalists.$t$, $t$It describes the issue accurately.$t$, $t$It discusses a relevant issue.$t$, $t$It presents a recent problem.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- Grade 9: Tesla's AI Robot Ready in September (258 words; printed 262)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 9 and test_type = 'pre' and title = $t$Tesla's AI Robot Ready in September$t$;
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
          jsonb_build_array($t$cook$t$, $t$drive$t$, $t$run$t$, $t$think$t$), 'a')
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
          jsonb_build_array($t$America has overtaken Japan and China in artificial intelligence competition.$t$, $t$America, Japan, and China were the three leading competitors in robot making.$t$, $t$Japan and China will also develop a humanoid robot-like Optimus.$t$, $t$Japan ang China will envy America for being able to develop a humanoid robot.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, null, $t$Which of the following is NOT discussed in the selection?$t$,
          jsonb_build_array($t$Artificial intelligence is becoming useful to people.$t$, $t$Modern technology can benefit everyone who can afford.$t$, $t$Technological advancement will always be beneficial.$t$, $t$Technology will always have good and bad effects.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$What is the meaning of the word "anticipation" in this sentence? The launch of this humanoid would be the first of its type, and a great deal of anticipation surrounds the event.$t$,
          jsonb_build_array($t$eagerness$t$, $t$expectation$t$, $t$prediction$t$, $t$suspension$t$), 'a')
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
          jsonb_build_array($t$disadvantages of the AI robot$t$, $t$distribution details of the Ai robot$t$, $t$estimate price of the AI robot$t$, $t$manufacturers of the AI robot$t$), 'a')
  on conflict (passage_id, question_no) do nothing;

  -- Grade 10: Butuan Archeological Sites (347 words; printed 350)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 10 and test_type = 'pre' and title = $t$Butuan Archeological Sites$t$;
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
end
$seed$;

-- Check (read-only): 7 passages, 6/7/8/10/10/10/10 questions, word counts as above.
-- select p.level, p.title, p.word_count, count(q.id) as questions
--   from public.phil_iri_passages p
--   join public.phil_iri_collections c on c.id = p.collection_id
--   left join public.phil_iri_questions q on q.passage_id = p.id
--  where c.school_id is null and c.name = 'Phil-IRI JHS 2024'
--  group by p.level, p.title, p.word_count order by p.level;
