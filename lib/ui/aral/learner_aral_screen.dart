// lib/ui/aral/learner_aral_screen.dart
// One ARAL learner: attendance, IRIP, check-ins, recommended materials and
// (SHARP only) the readability log, one tab each
// (docs/handoff/screens/aral.md: Sessions and attendance, IRIP, Check-ins,
// Materials and recommendations, Readability log).
import 'package:flutter/material.dart';

import '../../core/models/aral_session.dart';
import '../../viewmodels/aral_material_viewmodel.dart';
import '../../viewmodels/aral_session_viewmodel.dart';
import '../common/screen_kit.dart';
import 'aral_common.dart';
import 'checkin_view.dart';
import 'irip_view.dart';
import 'readability_view.dart';

/// Which tab opens first.
enum LearnerAralTab { attendance, irip, checkins, materials, readability }

class LearnerAralScreen extends StatelessWidget {
  final int enrollmentId;
  final String name;
  final LearnerAralTab initial;
  const LearnerAralScreen({super.key, required this.enrollmentId, required this.name, this.initial = LearnerAralTab.attendance});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: LearnerAralTab.values.length,
      initialIndex: initial.index,
      child: Scaffold(
        appBar: AppBar(
          title: Text(name),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Attendance'),
              Tab(text: 'IRIP'),
              Tab(text: 'Check-ins'),
              Tab(text: 'Materials'),
              Tab(text: 'Readability'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _Attendance(enrollmentId: enrollmentId),
            IripView(enrollmentId: enrollmentId),
            CheckinView(enrollmentId: enrollmentId),
            _Materials(enrollmentId: enrollmentId),
            ReadabilityView(enrollmentId: enrollmentId),
          ],
        ),
      ),
    );
  }
}

class _Attendance extends StatelessWidget {
  final int enrollmentId;
  const _Attendance({required this.enrollmentId});

  @override
  Widget build(BuildContext context) {
    return LoadView<(AralAttendanceSummary, List<(AralSession, AralAttendance)>)>(
      where: 'LearnerAral',
      load: (vms) => vms.aralSession.learnerAttendance(enrollmentId),
      builder: (context, data, _) {
        final (summary, list) = data;
        final theme = Theme.of(context);
        final rate = summary.rate;
        final stats = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Attendance', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            StatGrid(tileWidth: 180, tiles: [
              StatTile(label: 'Present', value: '${summary.present}', icon: aralMarkIcon(AralMark.present)),
              StatTile(label: 'Absent', value: '${summary.absent}', icon: aralMarkIcon(AralMark.absent)),
              StatTile(label: 'Excused', value: '${summary.excused}', icon: aralMarkIcon(AralMark.excused)),
              StatTile(label: 'Rate', value: rate == null ? '—' : '${(rate * 100).round()}%', icon: Icons.percent),
            ]),
            const SizedBox(height: 8),
            InfoRow('Rate', summary.label),
          ],
        );
        final sessions = list.isEmpty
            ? const EmptyNote('No sessions marked yet.', icon: Icons.event_note_outlined)
            : ListCard(
                title: 'Sessions',
                children: [
                  for (final (s, a) in list)
                    ListRow(
                      leading: LetterBadge('${s.sessionNo ?? '-'}'),
                      title: 'Session ${s.sessionNo ?? '-'} · ${s.heldOn}',
                      subtitle: s.lesson,
                      trailing: [StatusChip(a.mark.name, tone: aralMarkTone(a.mark), icon: aralMarkIcon(a.mark))],
                    ),
                ],
              );
        // Wide: sessions left, the summary right.
        if (MediaQuery.sizeOf(context).width >= 1000) {
          return PageBody(maxWidth: 1240, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: sessions),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: stats),
            ]),
          ]);
        }
        return PageBody(children: [stats, const SizedBox(height: 4), sessions]);
      },
    );
  }
}

class _Materials extends StatelessWidget {
  final int enrollmentId;
  const _Materials({required this.enrollmentId});

  @override
  Widget build(BuildContext context) {
    return LoadView<AralRecommendation>(
      where: 'LearnerAral',
      load: (vms) => vms.aralMaterial.recommendations(enrollmentId),
      builder: (context, r, _) => PageBody(
        children: [
          if (r.note != null) NoticeBanner(r.note!, icon: Icons.lightbulb_outline, tone: StatusTone.neutral),
          if (r.materials.isEmpty)
            const EmptyNote('No materials match this learner yet.', icon: Icons.menu_book_outlined)
          else
            ListCard(children: [
              for (final m in r.materials)
                ListRow(
                  leading: const IconBadge(Icons.menu_book_outlined),
                  title: m.material.title,
                  subtitle: [
                    m.material.kind.label,
                    m.material.language,
                    'Grades ${m.material.minGrade}–${m.material.maxGrade}',
                    ?m.material.fileName,
                  ].join(' · '),
                  trailing: [
                    if (m.link != null)
                      IconButton.filledTonal(
                        tooltip: 'Show link',
                        icon: const Icon(Icons.link),
                        onPressed: () => showTextDialog(context, title: m.material.title, text: m.link!),
                      ),
                  ],
                ),
            ]),
        ],
      ),
    );
  }
}
