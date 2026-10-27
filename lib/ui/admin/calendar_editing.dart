// lib/ui/admin/calendar_editing.dart
// The Round calendar's admin part: set a round's dates, skip it at a school,
// or clear the window. A superadmin (no school) sets the region defaults.
// Admin build only.
import 'package:flutter/material.dart';

import '../../core/models/assessment_calendar.dart';
import '../common/screen_kit.dart';
import '../common/signed_in_user.dart';
import '../dashboard/calendar_screen.dart';

class AdminCalendarEditor extends CalendarEditor {
  const AdminCalendarEditor();

  @override
  bool canEdit(BuildContext context) {
    final me = vmsOf(context).auth.currentUser;
    return me != null && isAdminOrCoordinator(me);
  }

  @override
  Future<bool> change(BuildContext context,
      {required int? schoolId,
      required String year,
      required CalendarInstrument instrument,
      required String round,
      required CalendarWindow? current}) async {
    final calendar = vmsOf(context).calendar;
    final action = await pickOne<String>(
      context,
      title: '${instrument.label} ${current?.roundLabel ?? round.toUpperCase()}',
      options: ['dates', if (schoolId != null) 'skip', if (current != null) 'clear'],
      label: (a) => switch (a) {
        'dates' => 'Set the dates',
        'skip' => 'Skip this round at this school',
        _ => schoolId == null ? 'Remove the region window' : 'Use the region default again',
      },
    );
    if (action == null || !context.mounted) return false;
    Object? done;
    if (action == 'dates') {
      final now = DateTime.now();
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(now.year - 2),
        lastDate: DateTime(now.year + 2),
        initialDateRange: current?.opensOn == null || current?.closesOn == null
            ? null
            : DateTimeRange(start: DateTime.parse(current!.opensOn!), end: DateTime.parse(current.closesOn!)),
      );
      if (range == null || !context.mounted) return false;
      done = await runAction(context, () => calendar.setWindow(schoolId, year, instrument, round, range.start, range.end),
          done: 'Window saved.', where: 'CalendarScreen');
    } else if (action == 'skip') {
      done = await runAction(context, () => calendar.skipRound(schoolId!, year, instrument, round),
          done: 'Round skipped.', where: 'CalendarScreen');
    } else {
      done = await runAction(context, () => calendar.clearWindow(schoolId, year, instrument, round),
          done: 'Window cleared.', where: 'CalendarScreen');
    }
    if (calendar.lastMirrorWarning != null && context.mounted) showNote(context, calendar.lastMirrorWarning!);
    return done != null;
  }
}
