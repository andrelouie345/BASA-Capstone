// lib/ui/dashboard/trends_screen.dart
// Trends (docs/handoff/screens/dashboard.md): a tutor sees their own ARAL
// activity (sessions, attendance); admins and coordinators pick a section,
// their school or the region and see Phil-IRI bands, round completion, CRLA
// profiles, ARAL exits and activity.
import 'package:flutter/material.dart';

import '../../core/models/report_setting.dart' show PhilIriValueList;
import '../../core/models/section.dart';
import '../../core/models/trend_chart.dart';
import '../../viewmodels/nla_report_viewmodel.dart' show nlaValuesLabel;
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
        maxWidth: 1200,
        children: [
          FilterBar(children: [
            SchoolYearPicker(value: _year, onChanged: (y) => setState(() => _year = y)),
            if (admin)
              SegmentedButton<_ScopeKind>(
                showSelectedIcon: false,
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
          ]),
          if (_year == null)
            const EmptyNote('Pick a school year to see its trends.', icon: Icons.insights_outlined)
          else if (scope == null)
            const EmptyNote('Pick a section to see its trends.', icon: Icons.class_outlined),
          if (_year != null && scope != null)
            LoadView<(List<(TrendChart, bool)>, String?)>(
              where: 'TrendsScreen',
              reloadKey: '$_year-$_kind-${_section?.id}',
              load: (vms) async {
                final t = vms.trend, y = _year!;
                final activity = await t.aralActivity(scope, y);
                if (!admin) return ([(activity.sessions, false), (activity.attendance, false)], null);
                // The band chart follows each school's Form 2b values switch.
                final bandSchool = switch (scope) {
                  SchoolScope(:final schoolId) => schoolId,
                  SectionScope() => _section?.schoolId,
                  _ => null,
                };
                final bandValues = bandSchool == null
                    ? "Values: each school's own Form 2b setting (carried or actual)"
                    : nlaValuesLabel(await vms.philIri.valueSource(bandSchool, PhilIriValueList.form2b));
                return (
                  [
                    (await t.completion(scope, y), false),
                    (await t.bandDistribution(scope, y), false),
                    (await t.crlaProfiles(scope, y), false),
                    (await t.aralExits(scope, y), false),
                    (activity.sessions, false),
                    (activity.attendance, false),
                  ],
                  bandValues,
                );
              },
              builder: (context, loaded, _) {
                final (charts, bandValues) = loaded;
                // Same order as the load above.
                final icons = charts.length == 2
                    ? const [Icons.event_repeat, Icons.how_to_reg_outlined]
                    : const [
                        Icons.task_alt,
                        Icons.stacked_bar_chart,
                        Icons.record_voice_over_outlined,
                        Icons.logout,
                        Icons.event_repeat,
                        Icons.how_to_reg_outlined,
                      ];
                return LayoutBuilder(
                  builder: (context, box) {
                    const gap = 12.0;
                    final w = box.maxWidth >= 1000 ? (box.maxWidth - gap) / 2 : box.maxWidth;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (var i = 0; i < charts.length; i++)
                          SizedBox(
                            width: w,
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                  TrendChartView(chart: charts[i].$1, percent: charts[i].$2, icon: icons[i % icons.length]),
                                  // The Form 2b band chart (second in the admin list).
                                  if (i == 1 && bandValues != null) ...[const SizedBox(height: 12), ValuesNote(bandValues)],
                                ]),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }
}
