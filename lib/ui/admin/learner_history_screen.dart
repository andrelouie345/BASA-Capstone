// lib/ui/admin/learner_history_screen.dart
// Learner history (docs/handoff/screens/admin.md): one learner's progress by
// school year from this device's records, found by LRN or opened from the
// Learners screen. A part this device can't read shows its note in place.
// Admin build only.
import 'package:flutter/material.dart';

import '../../viewmodels/learner_history_viewmodel.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';
import 'admin_scope.dart';

class LearnerHistoryScreen extends StatefulWidget {
  /// Opened from the Learners screen; null = search by LRN.
  final int? studentId;
  const LearnerHistoryScreen({super.key, this.studentId});

  @override
  State<LearnerHistoryScreen> createState() => _LearnerHistoryScreenState();
}

class _LearnerHistoryScreenState extends State<LearnerHistoryScreen> {
  final _lrn = TextEditingController();
  String? _search;

  @override
  void dispose() {
    _lrn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final history = AdminScope.of(context).learnerHistory;
    final id = widget.studentId;
    return Scaffold(
      appBar: AppBar(title: const Text('Learner history')),
      body: id == null && _search == null
          ? PageBody(
              maxWidth: 560,
              children: [
                TextField(
                  controller: _lrn,
                  decoration: const InputDecoration(labelText: 'LRN', prefixIcon: Icon(Icons.search)),
                  keyboardType: TextInputType.number,
                  onSubmitted: (v) => setState(() => _search = v.trim()),
                ),
                FilledButton(onPressed: () => setState(() => _search = _lrn.text.trim()), child: const Text('Find')),
              ],
            )
          : LoadView<LearnerHistory>(
              where: 'LearnerHistory',
              reloadKey: _search,
              load: (_) => id != null ? history.history(id) : history.historyByLrn(_search!),
              builder: (context, h, _) => PageBody(
                children: [
                  if (id == null)
                    TextButton.icon(
                      onPressed: () => setState(() => _search = null),
                      icon: const Icon(Icons.search),
                      label: const Text('Find another learner'),
                    ),
                  SectionCard(
                    title: studentLabel(h.student),
                    children: [
                      InfoRow('LRN', h.student.lrn),
                      if (h.student.sex != null) InfoRow('Sex', h.student.sex!),
                      if (h.scopeNote != null) Text(h.scopeNote!),
                    ],
                  ),
                  if (h.years.isEmpty) const EmptyNote('No records for this learner on this device.'),
                  for (final y in h.years) _YearCard(year: y),
                ],
              ),
            ),
    );
  }
}

class _YearCard extends StatelessWidget {
  final LearnerHistoryYear year;
  const _YearCard({required this.year});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget head(String s) => Padding(padding: const EdgeInsets.only(top: 10, bottom: 4), child: Text(s, style: text.titleSmall));
    return SectionCard(
      title: 'School year ${year.schoolYear}',
      children: [
        for (final e in year.enrollments)
          InfoRow('Section', 'Grade ${e.gradeLevel} ${e.sectionName} · ${e.schoolName ?? 'school not on this device'} · ${e.status}'),
        if (year.isEmpty) const Text('No assessments recorded'),
        if (year.crla.isNotEmpty) ...[
          head('CRLA'),
          for (final round in year.crla.entries)
            for (final test in round.value.entries) InfoRow('${round.key.label} · ${test.key}', test.value ?? 'no profile'),
        ],
        if (year.philIri.isNotEmpty) ...[
          head('Phil-IRI'),
          for (final p in year.philIri) ...[
            if (p.sectionName != null) Text(p.sectionName!, style: text.labelLarge),
            if (p.results == null)
              Text(p.unavailable ?? 'No results.')
            else
              for (final r in p.results!.rounds)
                InfoRow(
                  r.round.label,
                  r.notAssessed
                      ? 'not assessed'
                      : [
                          r.profile?.label ?? 'no profile',
                          if (r.adjustedLevelLabel != null) r.adjustedLevelLabel!,
                          if (r.isStrugglingReader) 'struggling reader',
                        ].join(' · '),
                ),
          ],
        ],
        for (final a in year.aral) ...[
          head('ARAL-Reading'),
          InfoRow('Program',
              '${a.enrollment.keyStage.label}${a.enrollment.track == null ? '' : ' ${a.enrollment.track!.label}'}'),
          InfoRow('Class', a.className == null ? 'waiting for a class' : '${a.className}${a.tutorName == null ? '' : ' · ${a.tutorName}'}'),
          InfoRow('Entered', '${a.enrollment.enteredOn} (${a.enrollment.basisSource.value})'),
          if (a.enrollment.referredBy != null)
            InfoRow('Referred by', '${a.enrollment.referredBy}${a.enrollment.referralReason == null ? '' : ': ${a.enrollment.referralReason}'}'),
          if (a.enrollment.exitedOn != null)
            InfoRow('Exited', '${a.enrollment.exitedOn} (${a.enrollment.exitReason?.value ?? ''})'),
          InfoRow('Attendance', a.attendance.label),
          if (a.unavailable != null)
            Text(a.unavailable!)
          else ...[
            InfoRow('16th-session check-in', _checkin(a.checkin16)),
            InfoRow('32nd-session check-in', _checkin(a.checkin32)),
          ],
        ],
        if (year.srp != null) ...[
          head('Summer Remediation'),
          InfoRow('Class', [year.srp!.className, ?year.srp!.tutorName, ?year.srp!.room].join(' · ')),
        ],
      ],
    );
  }
}

String _checkin(LearnerHistoryCheckin c) => switch (c) {
  LearnerHistoryCheckin.passed => 'passed',
  LearnerHistoryCheckin.failed => 'not passed',
  LearnerHistoryCheckin.notTaken => 'not taken',
  LearnerHistoryCheckin.unavailable => 'not available on this device',
};
