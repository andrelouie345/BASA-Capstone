-- Phil-IRI for JHS (2024), English posttest graded passages, Grades 4-10.
-- Source: Phil-IRI Manuals 2018 & 2024, "Teacher's Copy" of the posttest graded
-- passages and its Key to Correction (pp. 112-128 of the JHS part).
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
-- prints no count for Grades 4-6; Grades 7, 8 and 10 match the text, Grade 9
-- does not (printed 447, the text has 495 words). Printed counts are noted next
-- to each passage.
--
-- Question types (literal/inferential/critical) are not given for the graded
-- passages, so question_type stays null.--
-- Grade 10 Q2-Q4 share one stem and one list of situations in the manual; each
-- of those questions carries the stem and the situations here (the "(B)" answer
-- marks of the teacher's copy are left out; the key table has them). Q5 repeats
-- Q2 with the same key, as printed.
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

  -- Grade 4: Marian's Experiment (80 words; not printed)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 4 and test_type = 'post' and title = $t$Marian's Experiment$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', null, 4, $t$Marian's Experiment$t$,
            $t$What science experiment have you done?
In this selection, what was Marian's experiment?$t$,
            $t$Marian came home from school. She went to the kitchen and saw her mother cooking.
"Mama, do we have mongo seeds?" asked Marian. "I will do an experiment."
"Yes, we have some in the cabinet," answered Mama.
Marian got some seeds and planted them in a wooden box. She watered the seeds every day. She made sure they got enough sun. After three days, Marian was happy to see stems and leaves sprouting. Her mongo seeds grew into young plants.$t$,
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

  -- Grade 5: Trading Places (99 words; not printed)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 5 and test_type = 'post' and title = $t$Trading Places$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', null, 5, $t$Trading Places$t$,
            $t$Have you ever pretended to be someone else?
In this selection, find out what the main character pretended to be.$t$,
            $t$On a trip to a university, the driver told the professor, "I've heard you give this speech many times. I can deliver it for you." The professor said,
"The people in this university haven't seen me yet. Give the lecture. I'll pretend to be your driver."
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
  values (p, 5, null, $t$The driver tried to get out of a sticky situation. What was the sticky situation?$t$,
          jsonb_build_array($t$A participant recognized the professor.$t$, $t$The driver could not deliver the lecture.$t$, $t$The professor could not move from his seat.$t$, $t$The driver did not know what to answer.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$Why did the driver say "Even my driver can give you the answer!"?$t$,
          jsonb_build_array($t$to admit that even he did not know how to answer$t$, $t$to stop the audience from asking more questions$t$, $t$to stop the real professor from answering the question$t$, $t$to prove to the participants that the question was easy$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$He gave a very good speech and everybody applauded. Another word for applauded is ________________________.$t$,
          jsonb_build_array($t$kept very quiet$t$, $t$started to leave$t$, $t$clapped their hands$t$, $t$asked him to speak louder$t$), 'c')
  on conflict (passage_id, question_no) do nothing;

  -- Grade 6: Flying Rocks (139 words; not printed)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 6 and test_type = 'post' and title = $t$Flying Rocks$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'post', null, 6, $t$Flying Rocks$t$,
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
  values (p, 7, null, $t$Many asteroids must have collided with one another. What is a synonym of the word "collided"?$t$,
          jsonb_build_array($t$trapped into$t$, $t$crashed into$t$, $t$converged with$t$, $t$connected with$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$If you see faint flashes of light in the night sky, which of the following could have happened?$t$,
          jsonb_build_array($t$Flames shoot up from the sun and come closer to the earth.$t$, $t$Meteoroids have just crossed the earth's orbit and burned up.$t$, $t$Meteoroids have just crossed paths with the sun and burned up.$t$, $t$There are moments when the earth orbits a lot closer to the sun.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;

  -- Grade 7: The Jeepney: A Filipino Tradition (289 words; printed 289)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 7 and test_type = 'post' and title = $t$The Jeepney: A Filipino Tradition$t$;
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
          jsonb_build_array($t$One of the things that Filipinos love to do is travelling.$t$, $t$The American soldiers are very generous.$t$, $t$The Filipino version of the jeepney is more creative.$t$, $t$The jeepney is an original product of the Americans.$t$), 'd')
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
          jsonb_build_array($t$to convince people to disagree with the government's plan to replace the jeepneys$t$, $t$to emphasize the important role of jeepneys in the lives of the Filipinos$t$, $t$to enumerate the reasons why people consider jeepneys useful$t$, $t$to inform people about what happened to the jeeps left by the Americans$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 10, null, $t$Which of the following best presents a summary of the selection?$t$,
          jsonb_build_array($t$Americans gave the Filipinos their jeeps so that we can use them as vehicles.$t$, $t$Filipinos love the jeepneys because it is a safe way to travel around.$t$, $t$The government will phase out the jeepneys because they are not safe.$t$, $t$The jeepney, a popular vehicle in the Philippines is in danger of being phased out.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;

  -- Grade 8: The Impact of Social Media on Communication (303 words; printed 303)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 8 and test_type = 'post' and title = $t$The Impact of Social Media on Communication$t$;
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
          jsonb_build_array($t$by describing a series of events that happened$t$, $t$by giving examples of social media platforms$t$, $t$by narrating events in a random manner$t$, $t$by using ordinary and familiar terms$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, null, $t$Which of the following information is relevant to the discussion of social media in the selection?$t$,
          jsonb_build_array($t$being aware of privacy issues in social media$t$, $t$choosing the right kind of social media$t$, $t$communicating using social media$t$, $t$knowing what to post in social media$t$), 'd')
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
          jsonb_build_array($t$People who advertise their products in social media$t$, $t$People who like making friends through social media$t$, $t$People who love posting about their activities in social media$t$, $t$People who use social media to talk to families abroad$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 9, null, $t$What is the general tone of this article?$t$,
          jsonb_build_array($t$Critical- scrutinizes or judges the subject matter$t$, $t$Didactic-aims to educate or instruct the reader$t$, $t$Scholarly-tone is academic and intellectual; formal$t$, $t$Straightforward-present information clearly and simply$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 10, null, $t$What is the main purpose of the article?$t$,
          jsonb_build_array($t$To inform the readers about the increasing number of people destroyed by social media.$t$, $t$To persuade the readers to be more careful about what they share in social media$t$, $t$To remind the readers how social media has influenced the way we communicate$t$, $t$To tell the readers about the ease and convenience of using social media$t$), 'b')
  on conflict (passage_id, question_no) do nothing;

  -- Grade 9: The Rise of AI in Education (495 words; printed 447)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 9 and test_type = 'post' and title = $t$The Rise of AI in Education$t$;
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
          jsonb_build_array($t$how AI benefits learners with disabilities$t$, $t$how AI causes delay in ability to think$t$, $t$how AI helps teachers to save time$t$, $t$how transforms the learning process$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$What is the author suggesting in the last paragraph?$t$,
          jsonb_build_array($t$to continue using AI in the classroom$t$, $t$to fight the challenges brought forth by AI$t$, $t$to help teachers improve their AI knowledge$t$, $t$to identify the role that teachers play in using AI$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$Which of the following is used by the author in organizing ideas in one of the paragraphs?$t$,
          jsonb_build_array($t$describing common knowledge about AI$t$, $t$emphasizing the importance of data privacy$t$, $t$enumerating the disadvantages of using AI$t$, $t$giving examples of AI based platforms$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 9, null, $t$What is the general tone of the selection?$t$,
          jsonb_build_array($t$didactic-teaching readers what to do$t$, $t$objective-unbiased, neutral, fact-based$t$, $t$urgent-creates a sense importance$t$, $t$serious- urgent, not intended to entertain$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  -- CHECK: Q10 printed key is A (administrative efficiency), but paragraph 4 says AI brings "increased administrative efficiency", so A is discussed. Kept as printed.
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 10, null, $t$Which is NOT discussed in the selection?$t$,
          jsonb_build_array($t$how AI can increase administrative efficiency$t$, $t$how AI can promote inclusivity of learning$t$, $t$how AI serves ad hindrance to in person learning$t$, $t$how AI benefits struggling students$t$), 'a')
  on conflict (passage_id, question_no) do nothing;

  -- Grade 10: Exploring Non-Mendelian Genetics (446 words; printed 446)
  select id into p from public.phil_iri_passages
   where collection_id = c and level = 10 and test_type = 'post' and title = $t$Exploring Non-Mendelian Genetics$t$;
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
          jsonb_build_array($t$a child who inherited a combination of his mother (black) and father (white) skin$t$, $t$a child who inherited the blue eyes of his mother and the curly hair of his father$t$, $t$a child who inherited the brown skin of his mother and the height of his father$t$, $t$a child who inherited diabetes from his mother who got it from her grandmother$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, null, $t$What is the importance of knowing non-Mendelian genetics?$t$,
          jsonb_build_array($t$It challenges the classical rules of inheritance patterns established by Gregor Mendel.$t$, $t$It disproves the classical rules of inheritance patterns established by Gregor Mendel.$t$, $t$It expands the classical rules of inheritance patterns established by Gregor Mendel.$t$, $t$It improves the classical rules of inheritance patterns established by Gregor Mendel.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, null, $t$What is the purpose of the selection?$t$,
          jsonb_build_array($t$to argue about Gregor Mendel's classic theories on genetics$t$, $t$to describe the different rules of inheritance patterns$t$, $t$to inform readers about the limitations of the Mendelian theory$t$, $t$to persuade readers to consider non-Mendelian inheritance patterns$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, null, $t$Which of the following is NOT discussed in the selection$t$,
          jsonb_build_array($t$complexities of inheritance patterns$t$, $t$descriptions of genetic conditions$t$, $t$examples of non-Mendelian patterns$t$, $t$significance of genetic inheritance$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 9, null, $t$Which paragraph contains the topic sentence?$t$,
          jsonb_build_array($t$first paragraph$t$, $t$fourth paragraph$t$, $t$last paragraph$t$, $t$second paragraph$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 10, null, $t$How did the author organize the ideas in the selection?$t$,
          jsonb_build_array($t$by comparing and contrasting Mendelian and non-Mendelian rules of inheritance$t$, $t$by describing the characteristics of non-Mendelian genetic inheritance patterns$t$, $t$by inferring the cause and effects of the different inheritance patterns on people$t$, $t$by presenting the problems that humans may encounter because of genetic inheritance$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
end
$seed$;

-- Check (read-only): 7 passages, 6/7/8/10/10/10/10 questions, word counts as above.
-- select p.level, p.title, p.word_count, count(q.id) as questions
--   from public.phil_iri_passages p
--   join public.phil_iri_collections c on c.id = p.collection_id
--   left join public.phil_iri_questions q on q.passage_id = p.id
--  where c.school_id is null and c.name = 'Phil-IRI JHS 2024' and p.test_type = 'post'
--  group by p.level, p.title, p.word_count order by p.level;
