// lib/ui/admin/srp_editing.dart
// The SRP screen's admin part: the ranked candidates (with their CSV),
// building classes per section and class size, clearing them, and a
// class's name, room, schedule, tutor, learners and deletion. Admin build only.
import 'package:flutter/material.dart';

import '../../viewmodels/srp_viewmodel.dart';
import '../common/csv_table.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';
import '../common/signed_in_user.dart';
import '../reports/srp_screen.dart';

class AdminSrpEditor extends SrpEditor {
  const AdminSrpEditor();

  @override
  bool canEdit(BuildContext context) {
    final me = vmsOf(context).auth.currentUser;
    return me != null && isAdminOrCoordinator(me);
  }

  void _warn(BuildContext context) {
    final w = vmsOf(context).srp.lastMirrorWarning;
    if (w != null && context.mounted) showNote(context, w);
  }

  @override
  Future<bool> schoolActions(BuildContext context, int schoolId, String year) async {
    final srp = vmsOf(context).srp;
    final a = await pickOne<String>(context,
        title: 'SRP $year',
        options: const ['candidates', 'build', 'clear'],
        label: (a) => switch (a) {
          'candidates' => 'See the ranked candidates',
          'build' => 'Build classes from the candidates',
          _ => 'Delete every SRP class of this year',
        });
    if (a == null || !context.mounted) return false;
    switch (a) {
      case 'candidates':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _CandidatesScreen(schoolId: schoolId, year: year)));
        return false;
      case 'build':
        final f = await askFields(context, title: 'Build SRP classes', fields: [
          FieldSpec('per', 'Candidates per section', initial: '${srp.defaultPerSection}', number: true),
          FieldSpec('size', 'Class size', initial: '${srp.defaultClassSize}', number: true),
        ]);
        if (f == null || !context.mounted) return false;
        final per = int.tryParse(f['per']!) ?? srp.defaultPerSection, size = int.tryParse(f['size']!) ?? srp.defaultClassSize;
        final r = await runAction(context, () => srp.buildClasses(schoolId: schoolId, schoolYear: year, perSection: per, classSize: size),
            where: 'Srp');
        if (r != null && context.mounted) showNote(context, '${r.length} class(es) built.');
        if (context.mounted) _warn(context);
        return r != null;
      default:
        if (!await confirm(context, title: 'Delete every SRP class of $year?', action: 'Delete all', destructive: true) || !context.mounted) {
          return false;
        }
        final n = await runAction(context, () => srp.clearClasses(schoolId: schoolId, schoolYear: year), where: 'Srp');
        if (n != null && context.mounted) showNote(context, '$n class(es) deleted.');
        return n != null;
    }
  }

  @override
  Future<bool> classActions(BuildContext context, SrpClassView c, List<SrpClassView> all) async {
    final srp = vmsOf(context).srp;
    final k = c.srpClass;
    final a = await pickOne<String>(context,
        title: k.className,
        options: const ['details', 'move', 'remove', 'delete'],
        label: (a) => switch (a) {
          'details' => 'Name, room, schedule, tutor',
          'move' => 'Move a learner to another class',
          'remove' => 'Remove a learner',
          _ => 'Delete the class',
        });
    if (a == null || !context.mounted) return false;
    switch (a) {
      case 'details':
        final f = await askFields(context, title: k.className, fields: [
          FieldSpec('name', 'Class name', initial: k.className),
          FieldSpec('room', 'Room (empty = none)', initial: k.room ?? '', optional: true),
          FieldSpec('schedule', 'Schedule (empty = none)', initial: k.schedule ?? '', optional: true),
          FieldSpec('tutor', 'Tutor email (empty = none)', initial: c.tutor?.email ?? '', optional: true),
        ]);
        if (f == null || !context.mounted) return false;
        final r = await runAction(
          context,
          () => srp.updateClass(
            k.id!,
            className: f['name'],
            room: f['room']!.isEmpty ? null : f['room'],
            schedule: f['schedule']!.isEmpty ? null : f['schedule'],
            tutorEmail: f['tutor']!.isEmpty ? null : f['tutor'],
            clearRoom: f['room']!.isEmpty,
            clearSchedule: f['schedule']!.isEmpty,
            clearTutor: f['tutor']!.isEmpty,
          ),
          done: 'Class saved.',
          where: 'Srp',
        );
        if (context.mounted) _warn(context);
        return r != null;
      case 'move' || 'remove':
        if (c.learners.isEmpty) return false;
        final l = await pickOne(context,
            title: 'Learner',
            options: c.learners,
            label: (SrpClassLearner l) => l.student == null ? '#${l.member.studentId}' : studentLabel(l.student!));
        if (l == null || !context.mounted) return false;
        if (a == 'remove') {
          return await runAction(context, () => srp.removeLearner(k.id!, l.member.studentId), done: 'Removed.', where: 'Srp') != null;
        }
        final to = await pickOne<SrpClassView>(context,
            title: 'Move to', options: all.where((x) => x.srpClass.id != k.id).toList(), label: (x) => x.srpClass.className);
        if (to == null || !context.mounted) return false;
        return await runAction(context, () => srp.moveLearner(l.member.studentId, to.srpClass.id!), done: 'Moved.', where: 'Srp') != null;
      default:
        if (!await confirm(context, title: 'Delete ${k.className}?', action: 'Delete', destructive: true) || !context.mounted) return false;
        return runStep(context, () => srp.deleteClass(k.id!), done: 'Class deleted.', where: 'Srp');
    }
  }
}

class _CandidatesScreen extends StatelessWidget {
  final int schoolId;
  final String year;
  const _CandidatesScreen({required this.schoolId, required this.year});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('SRP candidates $year')),
      body: LoadView<SrpList>(
        where: 'SrpCandidates',
        load: (vms) => vms.srp.candidates(schoolId: schoolId, schoolYear: year),
        builder: (context, list, _) => PageBody(maxWidth: 1200, children: [
          Text('Ranked weakest first; the first ${list.perSection} of each section are recommended.'),
          CsvTableView(csv: srpListCsv(list), fileName: 'SRP_candidates_$year.csv'),
        ]),
      ),
    );
  }
}
