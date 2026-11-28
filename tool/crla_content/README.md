# CRLA content for digitized CRLA

Spec: `docs/superpowers/specs/2026-11-27-crla-digitized-design.md` (D1, D2).

The Region X forms (sample-files/crla/Region 10/) are typed into `supabase/seeds/crla_content/region10.json`:

```json
{
  "region_id": 13,
  "forms": [
    {
      "language": "English", "grade": 3, "variant": "eng",
      "tasks": {
        "task1": { "max": 10, "items": [ { "text": "bed" } ] },
        "task2": { "max": 10, "items": [ { "text": "clap" } ] }
      },
      "stories": [
        {
          "story_no": 1, "title": "Para the Parrot", "word_count": 100,
          "sentences": [ { "text": "Para flies away from the houses and into the market.", "words": 10 } ],
          "questions": [ { "after_sentence": 2, "question": "What must Para look for?",
                           "accepted_answers": "Any of these – fruits, food, what she can eat" } ]
        }
      ]
    }
  ]
}
```

- `language` and `title` exactly as `crla_stories` stores them (the Filipino package is `Tagalog`).
- `variant`: `eng` (tasks `task1`, `task2`) or `mt` / `fil` (tasks `task1`, `task2_low`, `task2_high`); it also
  decides the number of questions (`crlaComprehensionMax`).
- `items`: one entry per point, in the learner sheet's order. A sentence task lists each word as an item with
  `sentence_no` (1, 2, ...) so screens can show the sentence.
- A task whose sheet prints more items than it scores (two sentences of 11 words scored out of 10) gets
  `"form_miscount": true`: every printed word stays an item, the score is capped at `max`.
- `answer`: the printed correct response of an item the tutor checks against a key (Grade 1 rhyming word pairs:
  `"bulsa, tasa"` with `"answer": "Rhyme"`); left out for items read aloud.
- `sentences`: one entry per row of the record form's PASSAGE column, with its printed `# of words`.
  `after_sentence` = the row (1-based) the question is printed on. A row whose words differ from the printed count
  (the form miscounts it) keeps the printed `words` and gets `"form_miscount": true`: the printed counts are the
  official ones (the story's word count and the scoring use them); `check.dart` lists these rows as NOTE.
- Source: story rows and questions from `*LearnerRecordForm.pdf`, Part 1 items from `*Tool.pdf`.

Check, then build the seed:

```
dart run tool/crla_content/check.dart supabase/seeds/crla_content/region10.json <stories.csv>
dart run tool/crla_content/build_seed.dart supabase/seeds/crla_content/region10.json supabase/seeds/crla_content_region10.sql
```

`stories.csv` = `select language, grade, story_no, title, word_count from crla_stories where region_id = 13`.
The seed runs after migration `20261127010000` (it fills `crla_stories.body` and the new content tables).
