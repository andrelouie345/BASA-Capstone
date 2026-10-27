// lib/ui/aral/learner_pick_screen.dart
// The way into a learner's IRIP, check-ins or readability log from the
// home screen: the user's ARAL learners for a school year (a tutor's own
// classes, the school's for an admin or coordinator), then the learner's
// page on the right tab.
import 'package:flutter/material.dart';

import '../../core/models/aral_enrollment.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';
import '../common/signed_in_user.dart';
import 'aral_common.dart';
import 'learner_aral_screen.dart';

class AralLearnerPickScreen extends StatefulWidget {
  final String title;
  final LearnerAralTab tab;
  const AralLearnerPickScreen({super.key, required this.title, required this.tab});

  @override
  State<AralLearnerPickScreen> createState() => _AralLearnerPickScreenState();
}

class _AralLearnerPickScreenState extends State<AralLearnerPickScreen> {
  String? _year;
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final me = vmsOf(context).auth.currentUser;
    final admin = me != null && isAdminOrCoordinator(me);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: PageBody(
        children: [
          SchoolYearPicker(value: _year, onChanged: (y) => setState(() => _year = y)),
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search'),
            onChanged: (v) => setState(() => _filter = v.toLowerCase()),
          ),
          if (_year != null)
            LoadView<(List<AralEnrollment>, Map<int, String>)>(
              where: 'AralLearnerPick',
              reloadKey: _year,
              load: (vms) async {
                final list = admin && me.schoolId != null
                    ? await vms.aral.schoolRoster(schoolId: me.schoolId!, schoolYear: _year)
                    : await vms.aral.tutorRoster(tutorId: me?.id, schoolYear: _year);
                final active = list.where((e) => e.status == AralStatus.active).toList();
                return (active, await vms.aralSession.learnerNames(active));
              },
              builder: (context, data, _) {
                final (list, names) = data;
                final shown = list.where((e) => _filter.isEmpty || (names[e.studentId] ?? '').toLowerCase().contains(_filter)).toList();
                if (list.isEmpty) return const EmptyNote('No active ARAL learners for you this school year.');
                return Column(children: [
                  for (final e in shown)
                    Card(
                      child: ListTile(
                        title: Text(names[e.studentId] ?? 'Learner #${e.studentId}'),
                        subtitle: Text(aralProgramLabel(e)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => LearnerAralScreen(enrollmentId: e.id!, name: names[e.studentId] ?? 'Learner', initial: widget.tab),
                        )),
                      ),
                    ),
                ]);
              },
            ),
        ],
      ),
    );
  }
}
