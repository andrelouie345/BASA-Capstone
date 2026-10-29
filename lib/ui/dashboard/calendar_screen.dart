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
        maxWidth: 1200,
        children: [
          FilterBar(children: [SchoolYearPicker(value: _year, onChanged: (y) => setState(() => _year = y))]),
          if (schoolId == null) const NoticeBanner('Showing the region defaults.', icon: Icons.public, tone: StatusTone.neutral),
          if (_year != null)
            LoadView<(List<CalendarEntry>, List<CalendarWindow>)>(
              where: 'CalendarScreen',
              reloadKey: '$_year-$_reload',
              load: (vms) async =>
                  (await vms.calendar.effectiveCalendar(schoolId, _year!), await vms.calendar.invalidWindows(schoolId, _year!)),
              builder: (context, data, _) {
                final (entries, invalid) = data;
                final calendar = vmsOf(context).calendar;
                CalendarEntry? entryOf(CalendarInstrument instrument, String round) => entries
                    .where((e) => e.window.instrument == instrument && e.window.round == round)
                    .firstOrNull;
                // Summary: every round this app knows, by state.
                final counts = <String, int>{};
                for (final instrument in CalendarInstrument.values) {
                  for (final round in _rounds(instrument)) {
                    final w = entryOf(instrument, round)?.window;
                    final key = w == null || w.skipped ? 'none' : calendar.status(w).name;
                    counts[key] = (counts[key] ?? 0) + 1;
                  }
                }
                final cards = [
                  for (final instrument in CalendarInstrument.values)
                    ListCard(
                      title: instrument.label,
                      trailing: IconBadge(_instrumentIcon(instrument), size: 32),
                      children: [
                        for (final round in _rounds(instrument))
                          Builder(builder: (context) {
                            final e = entryOf(instrument, round);
                            final w = e?.window;
                            final status = w == null || w.skipped ? null : calendar.status(w);
                            final colors = Theme.of(context).colorScheme;
                            final muted = status == null;
                            return ListRow(
                              leading: IconBadge(
                                muted ? Icons.event_busy : Icons.event,
                                background: muted ? colors.surfaceContainerHigh : null,
                                foreground: muted ? colors.onSurfaceVariant : null,
                              ),
                              title: w?.roundLabel ?? round.toUpperCase(),
                              subtitle: w == null
                                  ? 'Not scheduled'
                                  : w.skipped
                                  ? 'Skipped at this school'
                                  : '${w.opensOn} to ${w.closesOn}${e!.isOverride ? ' · school dates' : ''}',
                              trailing: [
                                if (status != null)
                                  StatusChip(status.label, tone: _tone(status.name), icon: _statusIcon(status.name)),
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
                              ],
                            );
                          }),
                      ],
                    ),
                ];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StatGrid(tileWidth: 200, tiles: [
                      StatTile(label: 'Open now', value: '${counts['open'] ?? 0}', icon: Icons.lock_open),
                      StatTile(label: 'Upcoming', value: '${counts['upcoming'] ?? 0}', icon: Icons.schedule),
                      StatTile(label: 'Closed', value: '${counts['closed'] ?? 0}', icon: Icons.event_available),
                      StatTile(label: 'Not scheduled or skipped', value: '${counts['none'] ?? 0}', icon: Icons.event_busy),
                    ]),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, c) {
                        const gap = 12.0;
                        final w = c.maxWidth >= 1000 ? (c.maxWidth - gap) / 2 : c.maxWidth;
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [for (final card in cards) SizedBox(width: w, child: card)],
                        );
                      },
                    ),
                    if (invalid.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      ListCard(
                        title: 'INVALID (this app does not know these rounds)',
                        trailing: StatusChip('${invalid.length}', tone: StatusTone.bad),
                        children: [
                          for (final w in invalid)
                            Builder(builder: (context) {
                              final colors = Theme.of(context).colorScheme;
                              return ListRow(
                                leading: IconBadge(Icons.error_outline,
                                    background: colors.errorContainer, foreground: colors.onErrorContainer),
                                title: '${w.instrument.label} ${w.round}: ${w.opensOn} to ${w.closesOn}',
                              );
                            }),
                        ],
                      ),
                    ],
                  ],
                );
              },
            )
          else
            const EmptyNote('Pick a school year to see its round windows.', icon: Icons.calendar_month_outlined),
        ],
      ),
    );
  }
}

IconData _instrumentIcon(CalendarInstrument i) =>
    i == CalendarInstrument.crla ? Icons.record_voice_over_outlined : Icons.menu_book_outlined;

/// Round states by name (upcoming / open / closed).
StatusTone _tone(String status) => switch (status) {
  'open' => StatusTone.good,
  'upcoming' => StatusTone.warn,
  _ => StatusTone.neutral,
};

IconData _statusIcon(String status) => switch (status) {
  'open' => Icons.lock_open,
  'upcoming' => Icons.schedule,
  _ => Icons.check,
};
