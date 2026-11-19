// lib/ui/admin/aral_editing.dart
// The ARAL screens' admin parts: roster changes (propose, enroll, refer,
// placement, move, exit, reactivate, notes, remove, apply new results),
// classes (create, edit, delete, place, take out), settings and the
// material catalog. Admin build only; the shared screens in lib/ui/aral/
// show the data in both builds.
import 'package:flutter/material.dart';

import '../../core/models/aral_class.dart';
import '../../core/models/aral_enrollment.dart';
import '../../core/models/aral_material.dart';
import '../../core/models/report_setting.dart' show philIriValuesLabel;
import '../../core/models/section.dart';
import '../../core/models/student.dart';
import '../../viewmodels/aral_viewmodel.dart';
import '../aral/aral_common.dart';
import '../aral/aral_settings_screen.dart';
import '../aral/classes_screen.dart';
import '../aral/materials_screen.dart';
import '../aral/roster_screen.dart';
import '../common/pickers.dart';
import '../common/screen_kit.dart';
import '../common/signed_in_user.dart';

bool _isAdmin(BuildContext context) {
  final me = vmsOf(context).auth.currentUser;
  return me != null && isAdminOrCoordinator(me);
}

/// "KS2 Basic" style choices for a placement.
const _placements = <(AralKeyStage, AralTrack?)>[
  (AralKeyStage.foundational, null),
  (AralKeyStage.ks1, null),
  (AralKeyStage.ks2, AralTrack.basic),
  (AralKeyStage.ks2, AralTrack.plus),
  (AralKeyStage.ks3, AralTrack.basic),
  (AralKeyStage.ks3, AralTrack.plus),
];

/// What a proposal says about a learner, in words.
String _candidateLabel(AralCandidateStatus s) => switch (s) {
      AralCandidateStatus.proposed => 'proposed',
      AralCandidateStatus.notQualified => 'not needed (reads at grade level)',
      AralCandidateStatus.noResult => 'no result yet',
      AralCandidateStatus.enrolled => 'already on the roster',
    };

/// What "Update from results" did to a learner, in words.
String _updateLabel(AralUpdateKind k) => switch (k) {
      AralUpdateKind.programChanged => 'Program changed',
      AralUpdateKind.exited => 'Exited: reads at grade level',
      AralUpdateKind.refreshed => 'Same program, newer result',
      AralUpdateKind.unchanged => 'No change',
      AralUpdateKind.noResult => 'No result yet',
      AralUpdateKind.programMismatch => 'Not the program of their class',
      AralUpdateKind.otherGrade => 'Not the grade of their class',
      AralUpdateKind.unplaced => 'Waiting for a class',
      AralUpdateKind.otherSection => 'Now in another section',
      AralUpdateKind.leftSchool => 'Left the school',
    };

/// Why a learner leaves ARAL, in words.
String _exitLabel(AralExitReason r) => switch (r) {
      AralExitReason.gradeLevelReady => 'Reads at grade level',
      AralExitReason.transferredOut => 'Transferred out',
      AralExitReason.droppedOut => 'Dropped out',
      AralExitReason.classroomSupport => 'Classroom support is enough (KS1)',
      AralExitReason.other => 'Other reason',
    };

String _placementLabel((AralKeyStage, AralTrack?) p) => p.$2 == null ? p.$1.label : '${p.$1.label} ${p.$2!.label}';

Future<(AralKeyStage, AralTrack?)?> _pickPlacement(BuildContext context) =>
    pickOne(context, title: 'Program', options: _placements, label: _placementLabel);

// ---------------------------------------------------------------- roster

class AdminAralRosterEditor extends AralRosterEditor {
  const AdminAralRosterEditor();

  @override
  bool canEdit(BuildContext context) => _isAdmin(context);

  @override
  Future<bool> sectionActions(BuildContext context, Section section) async {
    final aral = vmsOf(context).aral;
    final a = await pickOne<String>(
      context,
      title: 'Enroll learners of $section',
      options: const ['propose', 'enroll', 'refer'],
      label: (a) => switch (a) {
        'propose' => 'See who BASA proposes (and enroll them all)',
        'enroll' => 'Enroll one learner',
        _ => 'Enroll a teacher referral',
      },
    );
    if (a == null || !context.mounted) return false;
    switch (a) {
      case 'propose':
        final list = await runAction(context, () => aral.propose(sectionId: section.id!, schoolYear: section.schoolYear), where: 'AralRoster');
        if (list == null || !context.mounted) return false;
        final proposed = list.where((c) => c.status == AralCandidateStatus.proposed).length;
        final text = [
          for (final c in list)
            '${studentLabel(c.student)}: ${_candidateLabel(c.status)}${c.suggestion == null ? '' : ' → ${c.suggestion!.label}'} (${c.reason})',
        ].join('\n');
        // Grades 4-10: which Phil-IRI values the proposals used (null for Grades 1-3).
        final values = aral.lastProposalValues;
        final body = text.isEmpty ? 'No learners.' : text;
        await showTextDialog(context,
            title: '$proposed proposed', text: values == null ? body : '${philIriValuesLabel(values)}\n\n$body');
        if (proposed == 0 || !context.mounted) return false;
        if (!await confirm(context, title: 'Enroll the $proposed proposed learner(s)?', action: 'Enroll') || !context.mounted) return false;
        final r = await runAction(context, () => aral.enrollProposed(sectionId: section.id!, schoolYear: section.schoolYear),
            where: 'AralRoster');
        if (r != null && context.mounted) showNote(context, 'Enrolled ${r.length} learner(s).');
        return r != null;
      case 'enroll' || 'refer':
        final learners = await runAction(context, () => vmsOf(context).student.localStudents(section.id!), where: 'AralRoster');
        if (learners == null || !context.mounted) return false;
        final s = await pickOne<Student>(context, title: 'Learner', options: learners, label: studentLabel);
        if (s == null || !context.mounted) return false;
        final p = await _pickPlacement(context);
        if (p == null || !context.mounted) return false;
        if (a == 'enroll') {
          return await runAction(
                context,
                () => aral.enroll(sectionId: section.id!, schoolYear: section.schoolYear, studentId: s.id!, keyStage: p.$1, track: p.$2),
                done: 'Enrolled.',
                where: 'AralRoster',
              ) !=
              null;
        }
        final f = await askFields(context, title: 'Referral', fields: const [
          FieldSpec('by', 'Referred by'),
          FieldSpec('why', 'Reason', multiline: true),
        ]);
        if (f == null || !context.mounted) return false;
        return await runAction(
              context,
              () => aral.refer(
                sectionId: section.id!,
                schoolYear: section.schoolYear,
                studentId: s.id!,
                keyStage: p.$1,
                track: p.$2,
                referredBy: f['by']!,
                reason: f['why']!,
              ),
              done: 'Referral enrolled.',
              where: 'AralRoster',
            ) !=
            null;
    }
    return false;
  }

  @override
  Future<bool> updateFromResults(BuildContext context, Section section) async {
    final aral = vmsOf(context).aral;
    if (!await confirm(context,
            title: 'Update the roster of $section?',
            body: "BASA reads the learners' newest CRLA and Phil-IRI results: a learner's program can change, and a "
                'learner who now reads at grade level exits ARAL.',
            action: 'Update') ||
        !context.mounted) {
      return false;
    }
    final r = await runAction(context, () => aral.applyResults(sectionId: section.id!, schoolYear: section.schoolYear), where: 'AralRoster');
    if (r == null || !context.mounted) return false;
    await showTextDialog(context,
        title: r.length == 1 ? '1 learner checked' : '${r.length} learners checked',
        text: r.isEmpty ? 'Nothing to update.' : r.map((u) => '${_updateLabel(u.kind)}: ${u.reason}').join('\n'));
    return r.isNotEmpty;
  }

  @override
  Future<bool> enrollmentActions(BuildContext context, AralEnrollment e) async {
    final aral = vmsOf(context).aral;
    final active = e.status == AralStatus.active;
    final a = await pickOne<String>(
      context,
      title: aralProgramLabel(e),
      options: [if (active) ...['placement', 'move', 'exit'] else 'reactivate', 'notes', 'remove'],
      label: (a) => switch (a) {
        'placement' => 'Change the program',
        'move' => 'Move to the learner\'s current section',
        'exit' => 'Exit from ARAL',
        'reactivate' => 'Reactivate',
        'notes' => 'Notes',
        _ => 'Remove from the roster',
      },
    );
    if (a == null || !context.mounted) return false;
    Future<bool> step(Future<Object?> Function() f, String done) async => await runAction(context, f, done: done, where: 'AralRoster') != null;
    switch (a) {
      case 'placement':
        final p = await _pickPlacement(context);
        if (p == null || !context.mounted) return false;
        return step(() => aral.setPlacement(e.id!, p.$1, p.$2), 'Program changed.');
      case 'move':
        return step(() => aral.moveToSection(e.id!), 'Moved.');
      case 'exit':
        final r = await pickOne<AralExitReason>(context,
            title: 'Why does the learner exit?', options: AralExitReason.values, label: _exitLabel);
        if (r == null || !context.mounted) return false;
        return step(() => aral.exit(e.id!, r), 'Exited.');
      case 'reactivate':
        return step(() => aral.reactivate(e.id!), 'Reactivated.');
      case 'notes':
        final f = await askFields(context, title: 'Notes', fields: const [FieldSpec('n', 'Notes', optional: true, multiline: true)]);
        if (f == null || !context.mounted) return false;
        return step(() => aral.setNotes(e.id!, f['n']!.isEmpty ? null : f['n']), 'Notes saved.');
      default:
        if (!await confirm(context, title: 'Remove from the roster?', body: 'Only for a learner enrolled by mistake.', action: 'Remove', destructive: true) ||
            !context.mounted) {
          return false;
        }
        return runStep(context, () => aral.remove(e.id!), done: 'Removed.', where: 'AralRoster');
    }
  }
}

// ---------------------------------------------------------------- classes

class AdminAralClassEditor extends AralClassEditor {
  const AdminAralClassEditor();

  @override
  bool canEdit(BuildContext context) => _isAdmin(context);

  // The year is shown because only learners of that year can be placed.
  Future<Map<String, String>?> _form(BuildContext context, {AralClass? c, String? schoolYear}) => askFields(context,
          title: c == null ? 'New class for ${schoolYear ?? ''}'.trim() : 'Edit class (${c.schoolYear})', fields: [
    if (c == null)
      const FieldSpec('name', 'Class name', optional: true,
          helper: 'Leave it empty for the next class code, e.g. ARAL-R-G7-01 (Reading, Grade 7, class 1).')
    else
      FieldSpec('name', 'Class name', initial: c.className),
    FieldSpec('grade', 'Home grade (1 to 10)', initial: c == null ? '' : '${c.gradeLevel}', number: true),
    FieldSpec('room', 'Room', initial: c?.room ?? '', optional: true),
    FieldSpec('schedule', 'Schedule', initial: c?.schedule ?? '', optional: true),
    FieldSpec('notes', 'Notes', initial: c?.notes ?? '', optional: true),
  ]);

  Future<(bool, AralClassProgram?)?> _program(BuildContext context) async {
    final p = await pickOne<String>(context,
        title: 'Program', options: ['mixed', ...AralClassProgram.values.map((p) => p.value)], label: (v) => v == 'mixed' ? 'Mixed programs' : AralClassProgram.values.firstWhere((p) => p.value == v).label);
    if (p == null) return null;
    return (true, p == 'mixed' ? null : AralClassProgram.values.firstWhere((x) => x.value == p));
  }

  /// The class's session type (ARAL memo item 14): (picked, value); null = cancelled.
  Future<(bool, AralSessionType?)?> _sessionType(BuildContext context) async {
    final t = await pickOne<String>(context,
        title: 'Session type',
        options: [...AralSessionType.values.map((t) => t.value), 'none'],
        label: (v) => v == 'none' ? 'Not set' : AralSessionType.values.firstWhere((t) => t.value == v).label);
    if (t == null) return null;
    return (true, t == 'none' ? null : AralSessionType.values.firstWhere((x) => x.value == t));
  }

  Future<String?> _tutor(BuildContext context, int schoolId, String year) async {
    final tutors = await runAction(context, () => vmsOf(context).aral.tutors(schoolId: schoolId, schoolYear: year), where: 'AralClasses');
    if (tutors == null || !context.mounted) return null;
    final t = await pickOne<String>(context,
        title: 'Tutor',
        options: ['none', ...tutors.map((t) => t.tutor.id)],
        label: (id) => id == 'none' ? 'No tutor yet' : () {
          final u = tutors.firstWhere((t) => t.tutor.id == id).tutor;
          return u.fullName.isEmpty ? u.email : u.fullName;
        }());
    return t;
  }

  @override
  Future<bool> addClass(BuildContext context, int schoolId, String schoolYear) async {
    final f = await _form(context, schoolYear: schoolYear);
    if (f == null || !context.mounted) return false;
    final grade = int.tryParse(f['grade']!);
    if (grade == null) {
      showNote(context, 'The grade must be a number.');
      return false;
    }
    final p = await _program(context);
    if (p == null || !context.mounted) return false;
    final tutor = await _tutor(context, schoolId, schoolYear);
    if (tutor == null || !context.mounted) return false;
    final type = await _sessionType(context);
    if (type == null || !context.mounted) return false;
    String? opt(String k) => f[k]!.isEmpty ? null : f[k];
    final vm = vmsOf(context).aralClass;
    final made = await runAction(
      context,
      () async => vm.createClass(
        schoolId: schoolId,
        schoolYear: schoolYear,
        // No name typed: the next memo-style code for that grade.
        className: opt('name') ?? await vm.suggestClassName(schoolId: schoolId, schoolYear: schoolYear, grade: grade),
        gradeLevel: grade,
        program: p.$2,
        tutorId: tutor == 'none' ? null : tutor,
        room: opt('room'),
        schedule: opt('schedule'),
        notes: opt('notes'),
        sessionType: type.$2,
      ),
      where: 'AralClasses',
    );
    if (made != null && context.mounted) showNote(context, 'Class "${made.className}" created.');
    return made != null;
  }

  /// True when the class is gone (the caller closes its page).
  @override
  Future<bool> classActions(BuildContext context, AralClass c) async {
    final vm = vmsOf(context).aralClass;
    final a = await pickOne<String>(context,
        title: c.className,
        options: const ['edit', 'program', 'tutor', 'session', 'delete'],
        label: (a) => switch (a) {
          'edit' => 'Edit name, grade, room, schedule',
          'program' => 'Change the program',
          'tutor' => 'Change the tutor',
          'session' => 'Change the session type',
          _ => 'Delete the class',
        });
    if (a == null || !context.mounted) return false;
    AralClass? changed;
    switch (a) {
      case 'edit':
        final f = await _form(context, c: c);
        if (f == null || !context.mounted) return false;
        String? opt(String k) => f[k]!.isEmpty ? null : f[k];
        changed = c.copyWith(
          className: f['name'],
          gradeLevel: int.tryParse(f['grade']!) ?? c.gradeLevel,
          room: () => opt('room'),
          schedule: () => opt('schedule'),
          notes: () => opt('notes'),
        );
      case 'program':
        final p = await _program(context);
        if (p == null || !context.mounted) return false;
        changed = c.copyWith(program: () => p.$2);
      case 'tutor':
        final t = await _tutor(context, c.schoolId, c.schoolYear);
        if (t == null || !context.mounted) return false;
        changed = c.copyWith(tutorId: () => t == 'none' ? null : t);
      case 'session':
        final t = await _sessionType(context);
        if (t == null || !context.mounted) return false;
        changed = c.copyWith(sessionType: () => t.$2);
      default:
        if (!await confirm(context, title: 'Delete ${c.className}?', action: 'Delete', destructive: true) || !context.mounted) return false;
        return runStep(context, () => vm.deleteClass(c.id!), done: 'Class deleted.', where: 'AralClasses');
    }
    final next = changed;
    await runAction(context, () => vm.editClass(next), done: 'Class saved.', where: 'AralClasses');
    return false;
  }

  @override
  Future<bool> place(BuildContext context, AralClass c) async {
    final vms = vmsOf(context);
    final waiting = await runAction(context, () async {
      final all = await vms.aral.schoolRoster(schoolId: c.schoolId, schoolYear: c.schoolYear);
      final list = all.where((e) => e.status == AralStatus.active && e.classId == null).toList();
      return (list, await vms.aralSession.learnerNames(list));
    }, where: 'AralClasses');
    if (waiting == null || !context.mounted) return false;
    final (list, names) = waiting;
    if (list.isEmpty) {
      showNote(context,
          "No learner is waiting for a class in ${c.schoolYear}. Learners waiting in other school years can't join this class.");
      return false;
    }
    final e = await pickOne<AralEnrollment>(context,
        title: 'Place in ${c.className}', options: list, label: (e) => '${names[e.studentId] ?? 'Learner'} · ${aralProgramLabel(e)}');
    if (e == null || !context.mounted) return false;
    // A learner of another grade needs the coordinator's confirmation.
    final otherGrade = await pickOne<bool>(context,
        title: 'Grade',
        options: const [false, true],
        label: (o) => o ? 'The learner is of another grade: place anyway' : 'The learner is of grade ${c.gradeLevel}');
    if (otherGrade == null || !context.mounted) return false;
    return await runAction(context, () => vms.aralClass.place(e.id!, c.id!, otherGrade: otherGrade), done: 'Placed.', where: 'AralClasses') !=
        null;
  }

  @override
  Future<bool> unplace(BuildContext context, AralEnrollment e) async {
    if (!await confirm(context, title: 'Take this learner out of the class?', body: 'They wait for a class again.', action: 'Take out') ||
        !context.mounted) {
      return false;
    }
    final vm = vmsOf(context).aralClass;
    return await runAction(context, () => vm.unplace(e.id!), done: 'Taken out.', where: 'AralClasses') != null;
  }
}

// ---------------------------------------------------------------- settings

class AdminAralSettingsEditor extends AralSettingsEditor {
  const AdminAralSettingsEditor();

  @override
  bool canEdit(BuildContext context) => _isAdmin(context);

  @override
  Future<bool> change(BuildContext context, int? schoolId, AralSettingKey key, Object current) async {
    final vm = vmsOf(context).aralCheckin;
    Future<bool> step(Future<Object?> Function() f) async => await runAction(context, f, done: 'Saved.', where: 'AralSettings') != null;
    if (current is bool) {
      final on = await pickOne<bool>(context, title: key == AralSettingKey.sharp ? 'SHARP' : 'KS1 extended', options: const [true, false], label: (b) => b ? 'On' : 'Off');
      if (on == null || !context.mounted) return false;
      return step(() => key == AralSettingKey.sharp ? vm.setFoundationalProgram(schoolId, on) : vm.setKs1Extended(schoolId, on));
    }
    final f = await askFields(context,
        title: key == AralSettingKey.passPct ? 'Check-in cut-off (%)' : 'Idle-session reminder (days)',
        fields: [FieldSpec('v', 'Value', initial: '$current', number: true)]);
    final v = int.tryParse(f?['v'] ?? '');
    if (v == null || !context.mounted) return false;
    return step(() => key == AralSettingKey.passPct ? vm.setPassPct(schoolId, v) : vm.setIdleSessionDays(schoolId, v));
  }

  @override
  Future<bool> changeRule(BuildContext context, int? schoolId, String key, Object? current) async {
    final vm = vmsOf(context).aralCheckin;
    final label = aralRuleLabels[key] ?? key;
    const useDefault = 'Use the region value / default';
    Object? value;
    if (current is bool || key == 'basis_round') {
      final choices = current is bool ? const ['On', 'Off', useDefault] : const ['BoSY', 'MoSY', useDefault];
      final pick = await pickOne<String>(context, title: label, options: choices, label: (c) => c);
      if (pick == null || !context.mounted) return false;
      value = switch (pick) { 'On' => true, 'Off' => false, 'BoSY' => 'bosy', 'MoSY' => 'mosy', _ => null };
    } else {
      final f = await askFields(context, title: label, fields: [
        FieldSpec('v', 'Value',
            initial: current is List ? current.join(',') : (current == null ? '' : '$current'),
            optional: true,
            hint: key == 'checkin_after_sessions' ? 'two sessions, e.g. 16,32' : null,
            helper: 'Leave it empty to use the region value or the default.'),
      ]);
      if (f == null || !context.mounted) return false;
      final text = f['v']!.trim();
      value = text.isEmpty ? null : vm.ruleSettingValue(key, text);
    }
    return await runAction(context, () => vm.setRuleSetting(schoolId, key, value),
            done: value == null ? 'School value removed.' : 'Saved.', where: 'AralRules') !=
        null;
  }

  @override
  Future<bool> reset(BuildContext context, int schoolId) async {
    if (!await confirm(context, title: "Use the region's ARAL settings?", action: 'Reset') || !context.mounted) return false;
    final vm = vmsOf(context).aralCheckin;
    return runStep(context, () => vm.resetSchoolSettings(schoolId), done: 'School settings removed.', where: 'AralSettings');
  }
}

// ---------------------------------------------------------------- materials

class AdminAralMaterialsEditor extends AralMaterialsEditor {
  const AdminAralMaterialsEditor();

  @override
  bool canEdit(BuildContext context) => _isAdmin(context);

  @override
  Future<bool> add(BuildContext context) async {
    final vm = vmsOf(context).aralMaterial;
    final schoolId = vmsOf(context).auth.currentUser?.schoolId;
    final p = await _pickPlacement(context);
    if (p == null || !context.mounted) return false;
    final kind = await pickOne<AralMaterialKind>(context, title: 'Kind', options: AralMaterialKind.values, label: (k) => k.label);
    if (kind == null || !context.mounted) return false;
    final f = await askFields(context, title: 'Add material', fields: const [
      FieldSpec('title', 'Title'),
      FieldSpec('language', 'Language', initial: 'English'),
      FieldSpec('min', 'Lowest grade', initial: '$aralMaterialDefaultMinGrade', number: true),
      FieldSpec('max', 'Highest grade', initial: '$aralMaterialDefaultMaxGrade', number: true),
      FieldSpec('file', 'File name', optional: true),
      FieldSpec('link', 'Link (e.g. Google Drive)', optional: true),
      FieldSpec('desc', 'Description', optional: true, multiline: true),
    ]);
    if (f == null || !context.mounted) return false;
    String? opt(String k) => f[k]!.isEmpty ? null : f[k];
    final made = await runAction(
      context,
      () => vm.addMaterial(
        schoolId: schoolId,
        title: f['title']!,
        keyStage: p.$1,
        track: p.$2,
        kind: kind,
        language: f['language']!,
        minGrade: int.tryParse(f['min']!) ?? aralMaterialDefaultMinGrade,
        maxGrade: int.tryParse(f['max']!) ?? aralMaterialDefaultMaxGrade,
        fileName: opt('file'),
        link: opt('link'),
        description: opt('desc'),
      ),
      done: 'Material added.',
      where: 'AralMaterials',
    );
    if (vm.lastMirrorWarning != null && context.mounted) showNote(context, vm.lastMirrorWarning!);
    return made != null;
  }

  @override
  Future<bool> actions(BuildContext context, AralMaterial m) async {
    final vm = vmsOf(context).aralMaterial;
    final schoolId = vmsOf(context).auth.currentUser?.schoolId;
    final a = await pickOne<String>(context,
        title: m.title,
        options: ['edit', m.isActive ? 'off' : 'on', if (schoolId != null) 'link', 'delete'],
        label: (a) => switch (a) {
          'edit' => 'Edit title, file name and link',
          'off' => 'Turn off',
          'on' => 'Turn on',
          'link' => "Set this school's own link",
          _ => 'Delete',
        });
    if (a == null || !context.mounted) return false;
    switch (a) {
      case 'edit':
        final f = await askFields(context, title: 'Edit material', fields: [
          FieldSpec('title', 'Title', initial: m.title),
          FieldSpec('file', 'File name', initial: m.fileName ?? '', optional: true),
          FieldSpec('link', 'Link', initial: m.link ?? '', optional: true),
        ]);
        if (f == null || !context.mounted) return false;
        String? opt(String k) => f[k]!.isEmpty ? null : f[k];
        return await runAction(context, () => vm.updateMaterial(m.id!, title: f['title'], fileName: () => opt('file'), link: () => opt('link')),
                done: 'Saved.', where: 'AralMaterials') !=
            null;
      case 'off' || 'on':
        return await runAction(context, () => vm.setActive(m.id!, a == 'on'), done: 'Saved.', where: 'AralMaterials') != null;
      case 'link':
        final f = await askFields(context, title: "This school's link", fields: const [FieldSpec('link', 'Link (empty = none)', optional: true)]);
        if (f == null || !context.mounted) return false;
        return await runAction(context, () => vm.setSchoolLink(m.id!, schoolId!, f['link']!.isEmpty ? null : f['link']),
                done: 'Saved.', where: 'AralMaterials') !=
            null || f['link']!.isEmpty;
      default:
        if (!await confirm(context, title: 'Delete ${m.title}?', action: 'Delete', destructive: true) || !context.mounted) return false;
        return runStep(context, () => vm.deleteMaterial(m.id!), done: 'Material deleted.', where: 'AralMaterials');
    }
  }
}
