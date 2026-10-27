// lib/ui/aral/sessions_screen.dart
// Sessions and attendance (docs/handoff/screens/aral.md): pick a class,
// see its sessions, log a new one (one per class per date), edit or delete
// it, and mark attendance on its sheet. Only the class tutor writes; the
// ViewModel refuses everyone else with its own message.
import 'package:flutter/material.dart';

import '../../core/models/aral_class.dart';
import '../../core/models/aral_session.dart';
import '../../viewmodels/aral_session_viewmodel.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';
import 'aral_common.dart';

class AralSessionsScreen extends StatefulWidget {
  const AralSessionsScreen({super.key});

  @override
  State<AralSessionsScreen> createState() => _AralSessionsScreenState();
}

class _AralSessionsScreenState extends State<AralSessionsScreen> {
  String? _year;
  AralClass? _class;
  int _reload = 0;

  Future<void> _log(AralClass c, [AralSession? s]) async {
    final r = await showDialog<_SessionForm>(context: context, builder: (_) => _SessionDialog(session: s));
    if (r == null || !mounted) return;
    final vm = vmsOf(context).aralSession;
    await runAction(
      context,
      () => s == null
          ? vm.logSession(classId: c.id!, heldOn: r.heldOn, minutes: r.minutes, setup: r.setup, lesson: r.lesson, remarks: r.remarks)
          : vm.editSession(s.id!, heldOn: r.heldOn, minutes: r.minutes, setup: r.setup, lesson: () => r.lesson, remarks: () => r.remarks),
      done: 'Session saved.',
      where: 'AralSessions',
    );
    setState(() => _reload++);
  }

  Future<void> _delete(AralSession s) async {
    if (!await confirm(context, title: 'Delete session ${s.sessionNo ?? ''}?', body: 'Its attendance is deleted too.', action: 'Delete', destructive: true) ||
        !mounted) {
      return;
    }
    final vm = vmsOf(context).aralSession;
    await runStep(context, () => vm.deleteSession(s.id!), done: 'Session deleted.', where: 'AralSessions');
    setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final schoolId = mySchoolId(context);
    final c = _class;
    return Scaffold(
      appBar: AppBar(title: const Text('Sessions and attendance')),
      floatingActionButton: c == null
          ? null
          : FloatingActionButton.extended(onPressed: () => _log(c), icon: const Icon(Icons.add), label: const Text('Log a session')),
      body: schoolId == null
          ? const NeedsSchoolNote()
          : PageBody(
              children: [
                SchoolYearPicker(value: _year, onChanged: (y) => setState(() => _year = y)),
                if (_year != null)
                  AralClassPicker(
                    schoolId: schoolId,
                    schoolYear: _year,
                    value: _class,
                    onChanged: (x) => setState(() => _class = x),
                  ),
                if (c != null)
                  LoadView<List<AralSession>>(
                    where: 'AralSessions',
                    reloadKey: '${c.id}-$_reload',
                    load: (vms) => vms.aralSession.classSessions(c.id!),
                    builder: (context, sessions, _) => Column(children: [
                      if (sessions.isEmpty) const EmptyNote('No sessions logged for this class yet.'),
                      for (final s in sessions.reversed)
                        Card(
                          child: ListTile(
                            leading: CircleAvatar(child: Text('${s.sessionNo ?? '-'}')),
                            title: Text('${s.heldOn} · ${s.minutes} min · ${s.setup.label}'),
                            subtitle: Text([?s.lesson, ?s.remarks].join('\n')),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) => v == 'edit' ? _log(c, s) : _delete(s),
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Text('Edit')),
                                PopupMenuItem(value: 'delete', child: Text('Delete')),
                              ],
                            ),
                            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AttendanceSheetScreen(session: s))),
                          ),
                        ),
                      const SizedBox(height: 72),
                    ]),
                  ),
              ],
            ),
    );
  }
}

class _SessionForm {
  final DateTime heldOn;
  final int minutes;
  final AralSetup setup;
  final String? lesson;
  final String? remarks;
  const _SessionForm(this.heldOn, this.minutes, this.setup, this.lesson, this.remarks);
}

class _SessionDialog extends StatefulWidget {
  final AralSession? session;
  const _SessionDialog({this.session});

  @override
  State<_SessionDialog> createState() => _SessionDialogState();
}

class _SessionDialogState extends State<_SessionDialog> {
  late DateTime _date = DateTime.tryParse(widget.session?.heldOn ?? '') ?? DateTime.now();
  late AralSetup _setup = widget.session?.setup ?? AralSetup.pullOut;
  late final _minutes = TextEditingController(text: '${widget.session?.minutes ?? 60}');
  late final _lesson = TextEditingController(text: widget.session?.lesson ?? '');
  late final _remarks = TextEditingController(text: widget.session?.remarks ?? '');

  @override
  void dispose() {
    _minutes.dispose();
    _lesson.dispose();
    _remarks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.session == null ? 'Log a session' : 'Edit session'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text('Held on ${isoDate(_date)}'),
              onTap: () async {
                final d = await pickDate(context, initial: isoDate(_date));
                if (d != null) setState(() => _date = DateTime.parse(d));
              },
            ),
            TextField(controller: _minutes, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minutes')),
            const SizedBox(height: 12),
            BasaDropdown<AralSetup>(
              label: 'Setup',
              items: AralSetup.values,
              value: _setup,
              itemLabel: (s) => s.label,
              onChanged: (s) => setState(() => _setup = s ?? _setup),
            ),
            const SizedBox(height: 12),
            TextField(controller: _lesson, decoration: const InputDecoration(labelText: 'Lesson (optional)')),
            const SizedBox(height: 12),
            TextField(controller: _remarks, decoration: const InputDecoration(labelText: 'Remarks (optional)')),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final m = int.tryParse(_minutes.text.trim());
            if (m == null) return;
            String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
            Navigator.of(context).pop(_SessionForm(_date, m, _setup, opt(_lesson), opt(_remarks)));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// A session's attendance sheet: tap present / absent / excused per learner.
class AttendanceSheetScreen extends StatefulWidget {
  final AralSession session;
  const AttendanceSheetScreen({super.key, required this.session});

  @override
  State<AttendanceSheetScreen> createState() => _AttendanceSheetScreenState();
}

class _AttendanceSheetScreenState extends State<AttendanceSheetScreen> {
  int _reload = 0;

  Future<void> _mark(int enrollmentId, AralMark? m) async {
    final vm = vmsOf(context).aralSession;
    final id = widget.session.id!;
    if (m == null) {
      await runStep(context, () => vm.unmark(id, enrollmentId), where: 'AttendanceSheet');
    } else {
      await runAction(context, () => vm.mark(id, enrollmentId, m), where: 'AttendanceSheet');
    }
    setState(() => _reload++);
  }

  Future<void> _rest(AralMark m) async {
    final vm = vmsOf(context).aralSession;
    await runAction(context, () => vm.markRest(widget.session.id!, m), done: 'Everyone else marked ${m.name}.', where: 'AttendanceSheet');
    setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Scaffold(
      appBar: AppBar(
        title: Text('Session ${s.sessionNo ?? ''} · ${s.heldOn}'),
        actions: [
          PopupMenuButton<AralMark>(
            tooltip: 'Mark the rest',
            icon: const Icon(Icons.done_all),
            onSelected: _rest,
            itemBuilder: (_) => [for (final m in AralMark.values) PopupMenuItem(value: m, child: Text('Mark the rest ${m.name}'))],
          ),
        ],
      ),
      body: LoadView<(List<AralSheetLine>, Map<int, String>)>(
        where: 'AttendanceSheet',
        reloadKey: _reload,
        load: (vms) async {
          final sheet = await vms.aralSession.sheet(s.id!);
          return (sheet, await vms.aralSession.learnerNames([for (final l in sheet) l.enrollment]));
        },
        builder: (context, data, _) {
          final (sheet, names) = data;
          return PageBody(children: [
            if (sheet.isEmpty) const EmptyNote('No learners in this class.'),
            for (final l in sheet)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(names[l.enrollment.studentId] ?? 'Learner', style: Theme.of(context).textTheme.titleSmall),
                    if (!l.expected) const Text('From another class'),
                    const SizedBox(height: 6),
                    SegmentedButton<AralMark?>(
                      emptySelectionAllowed: true,
                      segments: [for (final m in AralMark.values) ButtonSegment(value: m, label: Text(m.name))],
                      selected: {if (l.attendance != null) l.attendance!.mark},
                      onSelectionChanged: (sel) => _mark(l.enrollment.id!, sel.isEmpty ? null : sel.first),
                    ),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
