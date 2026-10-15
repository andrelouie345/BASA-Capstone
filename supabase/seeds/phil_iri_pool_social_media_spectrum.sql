-- "The Social Media Spectrum" (booklet code MoSYG08-RCH13): Grade 8 MOSY passage
-- for the "Phil-IRI Graded Passages (Level 2-10)" pool.
--
-- DRAFT QUESTIONS, for the reading coordinator's review. Run this only after she
-- approves them. The booklet's printed questions for this passage belong to
-- "The Impact of Social Media on Communication", so these 10 were written for
-- this text (owner, 2026-10-15). Once a learner has read the passage, its
-- questions are locked, so corrections are easiest before the first reading.
--
-- Text: as printed in the booklet (source spellquiz.com, reading test rch13);
-- 472 words, matching the printed count. Questions follow the booklet's MoSY
-- pattern: Q1-4 literal (L), Q5-7 inferential (I), Q8-10 critical (C); unlike the
-- printed sets, question_type is filled in.
--
-- Idempotent: run it in the SQL Editor as often as needed; existing rows are left
-- alone. Contains nothing that bypasses RLS.

do $seed$
declare
  c bigint;
  p bigint;
begin
  select id into c from public.phil_iri_collections
   where school_id is null and lower(name) = lower($t$Phil-IRI Graded Passages (Level 2-10)$t$);
  if c is null then
    raise exception 'Run phil_iri_graded_passages_pool.sql first (the pool collection is missing)';
  end if;

  select id into p from public.phil_iri_passages
   where collection_id = c and level = 8 and title = $t$The Social Media Spectrum$t$;
  if p is null then
    insert into public.phil_iri_passages
      (collection_id, language, test_type, set_code, level, title, motivation, body, word_count)
    values (c, 'English', 'mosy', $t$RCH13$t$, 8, $t$The Social Media Spectrum$t$,
            null,
            $t$In the digital age, social media has become a prominent feature of everyday life, especially for teenagers. Platforms like Instagram, TikTok, and Snapchat have redefined the way young people communicate, socialize, and perceive the world around them. While social media offers various benefits, it also presents unique challenges and impacts on individual behavior and society.
The positive aspects of social media are numerous. It allows teenagers to connect with friends and family members, regardless of their geographical location. It's a space where they can share experiences, celebrate milestones, and maintain relationships. Social media also serves as a platform for self-expression and creativity. Teenagers can explore their identities, discover new interests, and express themselves through photos, videos, and text.
Moreover, social media can be an informative resource. Teens have access to a wide range of information on current events, global issues, and educational content. This access can enhance their awareness and understanding of the world, encouraging them to be more informed and engaged citizens.
However, the influence of social media is not entirely positive. One significant issue is the impact on mental health. Constant exposure to the carefully curated images and lifestyles of others can lead to feelings of inadequacy and low self-esteem. Many teenagers find themselves comparing their lives to the seemingly perfect ones they see online, which can result in anxiety and depression.
Another concern is the aspect of cyberbullying. Social media platforms can sometimes become a venue for negative comments, harassment, and bullying. The anonymity and distance provided by these platforms can make some individuals feel they can act without consequences, often hurting others in the process.
Additionally, social media can contribute to a decrease in face-to-face interactions. Teens may prefer to communicate through their devices rather than engaging in real-life conversations, which can hinder the development of essential social skills. This digital communication often lacks the depth and emotional connection of personal interactions.
There's also the issue of distraction and time management. Many teenagers find themselves spending excessive amounts of time on social media, which can interfere with their studies, sleep, and real-life activities. The constant notifications and the urge to check updates can disrupt focus and reduce productivity.
Despite these challenges, teenagers continue to find value in social media. It's a tool that, when used responsibly, can enrich their lives. Educators and parents play a crucial role in guiding young people to use social media healthily and positively. They can teach teens about digital citizenship, which includes being respectful online, understanding the importance of privacy, and recognizing the difference between online personas and reality.
As social media continues to evolve, it's essential for teenagers to navigate this digital world with awareness and balance. Understanding the benefits and drawbacks of social media is key to using it in a way that enhances their lives without negatively impacting their well-being.$t$,
            472)
    returning id into p;
  end if;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 1, 'L', $t$According to the passage, which platforms have redefined the way young people communicate?$t$,
          jsonb_build_array($t$Facebook, Messenger, and Viber$t$, $t$YouTube, X, and WhatsApp$t$, $t$Skype, Zoom, and Telegram$t$, $t$Instagram, TikTok, and Snapchat$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 2, 'L', $t$Which of the following is NOT mentioned in the passage as a positive aspect of social media?$t$,
          jsonb_build_array($t$connecting with family members regardless of location$t$, $t$earning money through online businesses$t$, $t$expressing oneself through photos, videos, and text$t$, $t$having access to news on current events$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 3, 'L', $t$According to the passage, what can constant exposure to the carefully curated images and lifestyles of others lead to?$t$,
          jsonb_build_array($t$better time management$t$, $t$stronger face-to-face friendships$t$, $t$feelings of inadequacy and low self-esteem$t$, $t$more creative self-expression$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 4, 'L', $t$What makes some individuals feel they can act without consequences on social media?$t$,
          jsonb_build_array($t$the constant notifications$t$, $t$the educational content online$t$, $t$the guidance of parents and educators$t$, $t$the anonymity and distance the platforms provide$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 5, 'I', $t$In paragraph 4, what does the word "curated" most likely mean?$t$,
          jsonb_build_array($t$carefully selected and arranged$t$, $t$honestly and freely shared$t$, $t$quickly posted and deleted$t$, $t$copied from other people$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 6, 'I', $t$Why might a teenager who spends hours on social media every night do poorly in school?$t$,
          jsonb_build_array($t$Social media gives wrong information about school lessons.$t$, $t$Time spent online can take away time for studying and sleep.$t$, $t$Teachers do not allow students to use social media.$t$, $t$Online friends discourage teenagers from studying.$t$), 'b')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 7, 'I', $t$What does the title "The Social Media Spectrum" suggest about social media?$t$,
          jsonb_build_array($t$It is harmful to all teenagers.$t$, $t$It is mainly used for school work.$t$, $t$Its effects range from helpful to harmful.$t$, $t$Its colors and designs keep changing.$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 8, 'C', $t$Which statement best expresses the main idea of the passage?$t$,
          jsonb_build_array($t$Social media has both benefits and drawbacks, so teenagers should use it with awareness and balance.$t$, $t$Teenagers should stop using social media to protect their mental health.$t$, $t$Cyberbullying is the most serious problem caused by social media.$t$, $t$Social media is the best source of information for teenagers.$t$), 'a')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 9, 'C', $t$Which action best shows the "digital citizenship" described in the passage?$t$,
          jsonb_build_array($t$posting a classmate's embarrassing photo as a joke$t$, $t$sharing one's home address publicly to make new friends$t$, $t$being respectful to others online and keeping personal information private$t$, $t$believing everything that popular accounts post$t$), 'c')
  on conflict (passage_id, question_no) do nothing;
  insert into public.phil_iri_questions (passage_id, question_no, question_type, prompt, choices, answer_key)
  values (p, 10, 'C', $t$A friend feels sad after comparing her life with the posts of others. Which advice best follows the ideas in the passage?$t$,
          jsonb_build_array($t$Post more photos so that you will get more likes.$t$, $t$Remove all your friends from your account.$t$, $t$Stay online longer until you find happier posts.$t$, $t$Remember that posts often show only the best parts of people's lives, and spend time with people offline.$t$), 'd')
  on conflict (passage_id, question_no) do nothing;
end
$seed$;

-- Check (read-only): 1 passage, 472 words, 10 questions (keys D B C D A B C A C D).
-- select p.id, p.title, p.word_count, string_agg(q.answer_key, ' ' order by q.question_no) as keys
--   from public.phil_iri_passages p join public.phil_iri_questions q on q.passage_id = p.id
--  where p.title = 'The Social Media Spectrum' group by p.id;
