// lib/ui/dashboard/trends_screen.dart
// Trends (docs/handoff/screens/dashboard.md): a tutor sees their own ARAL
// activity (sessions, attendance); admins and coordinators pick a section,
// their school or the region and see Phil-IRI bands, round completion, CRLA
// profiles, ARAL exits and activity.
import 'package:flutter/material.dart';

import '../../core/models/section.dart';
import '../../core/models/trend_chart.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';
import '../common/signed_in_user.dart';
import 'trend_chart_view.dart';

class TrendsScreen extends StatefulWidget {
  const TrendsScreen({super.key});

  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

enum _ScopeKind { school, section, region }

class _TrendsScreenState extends State<TrendsScreen> {
  String? _year;
  _ScopeKind _kind = _ScopeKind.school;
  Section? _section;

  @override
  Widget build(BuildContext context) {
    final me = vmsOf(context).auth.currentUser;
    final admin = me != null && isAdminOrCoordinator(me);
    final TrendScope? scope = !admin
        ? TutorScope(me?.id)
        : switch (_kind) {
            _ScopeKind.school => me.schoolId == null ? const RegionScope() : SchoolScope(me.schoolId!),
            _ScopeKind.region => const RegionScope(),
            _ScopeKind.section => _section == null ? null : SectionScope(_section!.id!),
          };
    return Scaffold(
      appBar: AppBar(title: const Text('Trends')),
      body: PageBody(
        children: [
          SchoolYearPicker(value: _year, onChanged: (y) => setState(() => _year = y)),
          if (admin)
            SegmentedButton<_ScopeKind>(
              segments: [
                ButtonSegment(value: _ScopeKind.school, label: Text(me.schoolId == null ? 'All schools' : 'My school')),
                const ButtonSegment(value: _ScopeKind.section, label: Text('A section')),
                if (me.schoolId == null) const ButtonSegment(value: _ScopeKind.region, label: Text('Region')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
          if (admin && _kind == _ScopeKind.section)
            SectionPicker(value: _section, onChanged: (s) => setState(() => _section = s)),
          if (_year != null && scope != null)
            LoadView<List<(TrendChart, bool)>>(
              where: 'TrendsScreen',
              reloadKey: '$_year-$_kind-${_section?.id}',
              load: (vms) async {
                final t = vms.trend, y = _year!;
                final activity = await t.aralActivity(scope, y);
                if (!admin) return [(activity.sessions, false), (activity.attendance, false)];
                return [
                  (await t.completion(scope, y), false),
                  (await t.bandDistribution(scope, y), false),
                  (await t.crlaProfiles(scope, y), false),
                  (await t.aralExits(scope, y), false),
                  (activity.sessions, false),
                  (activity.attendance, false),
                ];
              },
              builder: (context, charts, _) => Column(
                children: [
                  for (final (c, pct) in charts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(child: Padding(padding: const EdgeInsets.all(16), child: TrendChartView(chart: c, percent: pct))),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
