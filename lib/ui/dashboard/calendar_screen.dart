// lib/ui/dashboard/calendar_screen.dart
// Round calendar (docs/handoff/screens/dashboard.md): each instrument's round
// windows for a year (region default, school override or skipped) and
// whether each is upcoming, open or closed. Setting, skipping and clearing
// windows is admin-only: the admin build passes a [CalendarEditor]
// (lib/ui/admin/), so the tutor build never contains it.
import 'package:flutter/material.dart';

import '../../core/models/assessment_calendar.dart';
import '../../core/models/crla_assessment.dart';
import '../../core/models/phil_iri_assessment.dart';
import '../../viewmodels/round_calendar_viewmodel.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';

/// The admin build's calendar changes. Returns true when something changed.
abstract class CalendarEditor {
  const CalendarEditor();
  bool canEdit(BuildContext context);
  Future<bool> change(BuildContext context,
      {required int? schoolId,
      required String year,
      required CalendarInstrument instrument,
      required String round,
      required CalendarWindow? current});
}

class CalendarScreen extends StatefulWidget {
  final CalendarEditor? editor;
  const CalendarScreen({super.key, this.editor});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  String? _year;
  int _reload = 0;

  List<String> _rounds(CalendarInstrument i) => switch (i) {
    CalendarInstrument.crla => [for (final r in CrlaRound.values) r.name],
    _ => [for (final r in PhilIriRound.values) r.name],
  };

  @override
  Widget build(BuildContext context) {
    final me = vmsOf(context).auth.currentUser;
    final schoolId = me?.schoolId;
    final editor = widget.editor;
    final canEdit = editor != null && editor.canEdit(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Round calendar')),
      body: PageBody(
        children: [
          SchoolYearPicker(value: _year, onChanged: (y) => setState(() => _year = y)),
          if (schoolId == null) const Text('Showing the region defaults.'),
          if (_year != null)
            LoadView<(List<CalendarEntry>, List<CalendarWindow>)>(
              where: 'CalendarScreen',
              reloadKey: '$_year-$_reload',
              load: (vms) async =>
                  (await vms.calendar.effectiveCalendar(schoolId, _year!), await vms.calendar.invalidWindows(schoolId, _year!)),
              builder: (context, data, _) {
                final (entries, invalid) = data;
                final calendar = vmsOf(context).calendar;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final instrument in CalendarInstrument.values)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SectionCard(
                          title: instrument.label,
                          children: [
                            for (final round in _rounds(instrument))
                              Builder(builder: (context) {
                                final e = entries
                                    .where((e) => e.window.instrument == instrument && e.window.round == round)
                                    .firstOrNull;
                                final w = e?.window;
                                final status = w == null || w.skipped ? null : calendar.status(w);
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(w?.roundLabel ?? round.toUpperCase()),
                                  subtitle: Text(w == null
                                      ? 'Not scheduled'
                                      : w.skipped
                                      ? 'Skipped at this school'
                                      : '${w.opensOn} to ${w.closesOn}${e!.isOverride ? ' · school dates' : ''}'),
                                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                    if (status != null) Chip(label: Text(status.label)),
                                    if (canEdit)
                                      IconButton(
                                        tooltip: 'Change',
                                        icon: const Icon(Icons.edit_calendar),
                                        onPressed: () async {
                                          final changed = await editor.change(context,
                                              schoolId: schoolId,
                                              year: _year!,
                                              instrument: instrument,
                                              round: round,
                                              current: e?.isOverride == true || schoolId == null ? w : null);
                                          if (changed && mounted) setState(() => _reload++);
                                        },
                                      ),
                                  ]),
                                );
                              }),
                          ],
                        ),
                      ),
                    if (invalid.isNotEmpty)
                      SectionCard(
                        title: 'INVALID (this app does not know these rounds)',
                        children: [for (final w in invalid) Text('${w.instrument.label} ${w.round}: ${w.opensOn} to ${w.closesOn}')],
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
