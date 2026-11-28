// No-improvement alerts on the reminders (spec
// docs/superpowers/specs/2026-11-27-aral-effectiveness-design.md D1): one tutor
// line per own class with flagged learners, one coordinator notice per class.
import 'dart:io';

import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';
import 'package:basa_capstone/viewmodels/reminder_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/offline_owner.dart';

const _year = '2026-2027';
const _a = '00000000-0000-0000-0000-0000000000a1'; // tutor of class 1
const _b = '00000000-0000-0000-0000-0000000000b1'; // tutor of class 2
const _coord = '00000000-0000-0000-0000-0000000000c1';
final _today = DateTime(2026, 11, 27);

void main() {
  late AppContext ctx;
  late TutorVms t;
  late Database db;

  Future<void> signIn(String id, String role) async {
    await ctx.authVm.signOut();
    await seedOfflineOwner(db, userId: id, email: '$id@t', role: role, schoolId: 1);
    expect(await ctx.authVm.signInOffline(email: '$id@t', password: 'test-pw'), isNull);
  }

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    ctx = await AppContext.open(dataDir: Directory.systemTemp.createTempSync('basa_no_impr_rem_').path);
    t = wireTutor(ctx, wireShared(ctx));
    db = ctx.localDb;
    await db.insert('schools', {'id': 1, 'school_id': 'ZZNR1', 'school_name': 'ZZ No improvement reminders', 'region_id': 13});
    for (final (id, grade) in [(71, '2'), (72, '7')]) {
      await db.insert('sections', {'id': id, 'school_id': 1, 'school_year': _year, 'grade_level': grade, 'section_name': 'S$id'});
    }
    for (final u in [_a, _b]) {
      await db.insert('users', {'id': u, 'email': '$u@t', 'full_name': 'Tutor', 'role': 'tutor', 'school_id': 1, 'is_active': 1});
    }
    for (final (id, tutor) in [(1, _a), (2, _b), (3, null)]) {
      await db.insert('aral_classes', {'id': id, 'school_id': 1, 'school_year': _year, 'class_name': 'ARAL-R-0$id',
          'grade_level': 2, 'tutor_id': tutor, 'origin': 'cloud', 'row_version': 1});
    }
    // 1, 2 class 1 (same); 3 class 2 (up); 4 class 3, no tutor (same); 5 Grade 7
    // in class 1, no reading, no check-in (check-in due, not flagged).
    final classOf = {1: 1, 2: 1, 3: 2, 4: 3, 5: 1};
    for (final e in classOf.entries) {
      final s = e.key;
      final section = s == 5 ? 72 : 71;
      await db.insert('students', {'id': s, 'lrn': '99970000000$s', 'last_name': 'R$s', 'first_name': 'F', 'school_id': 1});
      await db.insert('enrollments', {'student_id': s, 'section_id': section, 'school_year': _year, 'status': 'active'});
      await db.insert('aral_enrollments', {
        'id': s, 'student_id': s, 'school_id': 1, 'section_id': section, 'school_year': _year,
        'key_stage': s == 5 ? 'ks3' : 'ks1', 'track': s == 5 ? 'basic' : null, 'class_id': e.value,
        'status': 'active', 'entered_on': '2026-07-01', 'basis_source': s == 5 ? 'phil_iri' : 'crla',
        'basis_round': 'bosy', 'basis_level': 'x', 'origin': 'cloud', 'row_version': 1,
      });
    }
    var id = 100;
    for (final s in [1, 2, 3, 4]) {
      for (final (round, day, attempt) in [('bosy', '2026-08-03', 1), ('mosy', '2026-10-05', 2)]) {
        await db.insert('crla_assessments', {
          'id': ++id, 'student_id': s, 'school_id': 1, 'section_id': 71, 'school_year': _year, 'subject_variant': 'fil',
          'language': 'Tagalog', 'round': round, 'attempt_no': attempt, 'assessed_at': day, 'origin': 'cloud',
          'row_version': 1,
          'reading_profile': s == 3 && round == 'mosy' ? 'Developing Reader' : 'High Emerging Reader',
        });
      }
    }
    // 16 sessions per class before the MOSY date; every class learner present.
    var sid = 1000;
    var markId = 5000;
    for (final cls in [1, 2, 3]) {
      for (var i = 0; i < 16; i++) {
        final day = DateTime(2026, 8, 1).add(Duration(days: i * 3)).toIso8601String().substring(0, 10);
        await db.insert('aral_sessions', {'id': ++sid, 'tutor_id': cls == 2 ? _b : _a, 'school_id': 1,
            'school_year': _year, 'session_no': i + 1, 'held_on': day, 'minutes': 60, 'setup': 'pull_out',
            'class_id': cls, 'origin': 'cloud', 'row_version': 1});
        for (final s in classOf.keys.where((s) => classOf[s] == cls)) {
          await db.insert('aral_attendance',
              {'id': ++markId, 'session_id': sid, 'enrollment_id': s, 'mark': 'present', 'row_version': 1});
        }
      }
    }
    await db.insert('aral_checkin_tools', {'id': 1, 'key_stage': 'ks3', 'track': 'basic', 'checkpoint': 16,
        'language': 'english', 'title': 'ZZ check-in 16'});
    await db.insert('aral_checkin_items', {'id': 1, 'tool_id': 1, 'item_no': 1, 'kind': 'open', 'prompt': 'Read.'});
  });

  test('tutor: one line for their class, after the check-ins due, learners with reasons', () async {
    await signIn(_a, 'tutor');
    final rs = (await t.reminderVm.tutorReminders(_a, _year, today: _today)).reminders;
    final lines = rs.where((r) => r.kind == TutorReminderKind.noImprovement).toList();
    expect(lines.map((r) => (r.aralClass?.id, r.message)), [(1, 'Class "ARAL-R-01": 2 learners show no improvement.')]);
    expect(lines.single.learners.map((l) => (l.studentId, l.lrn, l.enrollmentId, l.reasons.join(' | '))), [
      (1, '999700000001', 1, 'Same since BOSY: High Emerging Reader -> High Emerging Reader (MOSY)'),
      (2, '999700000002', 2, 'Same since BOSY: High Emerging Reader -> High Emerging Reader (MOSY)'),
    ]);
    final kinds = rs.map((r) => r.kind).toList();
    expect(kinds.indexOf(TutorReminderKind.checkinDue), lessThan(kinds.indexOf(TutorReminderKind.noImprovement)));
    // Other reminders' learners carry no reasons.
    expect(rs.where((r) => r.kind != TutorReminderKind.noImprovement).expand((r) => r.learners).every((l) => l.reasons.isEmpty),
        isTrue);
  });

  test('tutor: a class with nobody flagged gets no line', () async {
    await signIn(_b, 'tutor');
    final rs = (await t.reminderVm.tutorReminders(_b, _year, today: _today)).reminders;
    expect(rs.where((r) => r.kind == TutorReminderKind.noImprovement), isEmpty);
  });

  test('coordinator: a notice per class with flagged learners, also a class without a tutor', () async {
    await signIn(_coord, 'coordinator');
    final school = (await t.reminderVm.coordinatorReminders(1, _year, today: _today)).single;
    final notices = school.aral.where((n) => n.kind == AralClassNoticeKind.noImprovement).toList();
    expect(notices.map((n) => (n.aralClass?.id, n.message)), [
      (1, 'Class "ARAL-R-01": 2 learners show no improvement.'),
      (3, 'Class "ARAL-R-03": 1 learner shows no improvement.'),
    ]);
    expect(notices.last.learners.single.reasons, hasLength(1));
  });
}
