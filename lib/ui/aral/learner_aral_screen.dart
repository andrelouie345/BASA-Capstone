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
        return PageBody(
          children: [
            SectionCard(title: 'Attendance', children: [
              InfoRow('Present', '${summary.present}'),
              InfoRow('Absent', '${summary.absent}'),
              InfoRow('Excused', '${summary.excused}'),
              InfoRow('Rate', summary.label),
            ]),
            SectionCard(
              title: 'Sessions',
              children: [
                if (list.isEmpty) const Text('No sessions marked yet.'),
                for (final (s, a) in list)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('Session ${s.sessionNo ?? '-'} · ${s.heldOn}'),
                    subtitle: s.lesson == null ? null : Text(s.lesson!),
                    trailing: Text(a.mark.name),
                  ),
              ],
            ),
          ],
        );
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
          if (r.note != null) Text(r.note!),
          if (r.materials.isEmpty) const EmptyNote('No materials match this learner yet.'),
          for (final m in r.materials)
            Card(
              child: ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(m.material.title),
                subtitle: Text([
                  m.material.kind.label,
                  m.material.language,
                  'Grades ${m.material.minGrade}–${m.material.maxGrade}',
                  ?m.material.fileName,
                ].join(' · ')),
                trailing: m.link == null
                    ? null
                    : IconButton(
                        tooltip: 'Show link',
                        icon: const Icon(Icons.link),
                        onPressed: () => showTextDialog(context, title: m.material.title, text: m.link!),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}
