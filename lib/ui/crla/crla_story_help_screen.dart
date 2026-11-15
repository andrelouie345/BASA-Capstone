// lib/ui/crla/crla_story_help_screen.dart
// "Story number and words read": what the two Part 2 fields mean, where the
// story number comes from and who to ask (owner 2026-11-15: coordinators tell
// tutors which story to use). Opened from the Part 2 form's "?" and the
// Part 2 card. Both builds.
import 'package:flutter/material.dart';

import '../common/screen_kit.dart';

class CrlaStoryHelpScreen extends StatelessWidget {
  const CrlaStoryHelpScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CrlaStoryHelpScreen()));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Story number and words read')),
      body: PageBody(
        maxWidth: 820,
        children: [
          const NoticeBanner(
            'Not sure which story to use? Ask your coordinator before you assess. '
            'Coordinators tell tutors which story number to use.',
            icon: Icons.support_agent_outlined,
          ),
          SectionCard(
            title: 'Story number',
            icon: Icons.menu_book_outlined,
            children: const [
              _Para('Part 2 of the CRLA has two stories for each grade and language: story 1 and story 2. '
                  'The number and the title are printed on the Part 2 learner sheet, and at the top of the '
                  "record form's Part 2 page (for example \"STORY 1 – PARA THE PARROT\")."),
              _Para('Enter the number of the story the learner read. The Part 2 form lists the stories for this '
                  "attempt (your school's region, the attempt's language, the section's grade) with their titles, "
                  'so you can match the title on your sheet.'),
              _Para('The number matters: BASA scores the reading with that story\'s word count. A wrong number '
                  'gives a wrong words read, words per minute and reading profile. If you saved the wrong one, '
                  'open Part 2 again and change it.'),
            ],
          ),
          SectionCard(
            title: 'Words read',
            icon: Icons.format_list_numbered,
            children: const [
              _Para("Words read is the story's number of words minus the miscues, as on the DepEd CRLA "
                  'scoresheet.'),
              _Para('When the Part 2 form lists the stories, leave words read blank: BASA works it out from the '
                  'story and the miscues.'),
              _Para('When the form says there is no story list for this attempt, BASA does not know the story\'s '
                  "words. Take the TOTAL number of words from the record form's Part 2 page, subtract the "
                  'miscues, and type the result.'),
            ],
          ),
          SectionCard(
            title: 'Fixing a mistake',
            icon: Icons.build_outlined,
            children: const [
              _Para('A wrong score in Part 1 or Part 2: open the attempt and use Change.'),
              _Para('An attempt started by mistake (wrong learner, test, language or round) can be removed, '
                  'but only while it is still only on this device (not uploaded), and only if it is the '
                  "learner's latest attempt for that test. Remove it before you start another one."),
              NoticeBanner(
                'Once an attempt is uploaded it stays and cannot be removed here. Ask your coordinator.',
                icon: Icons.warning_amber_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Para extends StatelessWidget {
  final String text;
  const _Para(this.text);

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(text, style: Theme.of(context).textTheme.bodyMedium));
}
