// Reports and calendar values a screen reads through ViewModels and models
// (spec docs/superpowers/specs/2026-10-24-vm-completeness-design.md,
// REPORTS-G2/G3, DASH-G1/G4).
import 'package:basa_capstone/core/console/logger.dart';
import 'package:basa_capstone/core/models/assessment_calendar.dart';
import 'package:basa_capstone/core/models/srp_class.dart';
import 'package:basa_capstone/core/models/user_role.dart';
import 'package:basa_capstone/core/repositories/assessment_calendar_repository.dart';
import 'package:basa_capstone/core/repositories/section_repository.dart';
import 'package:basa_capstone/core/repositories/srp_class_repository.dart';
import 'package:basa_capstone/core/repositories/student_repository.dart';
import 'package:basa_capstone/core/repositories/user_repository.dart';
import 'package:basa_capstone/core/services/srp_rules.dart';
import 'package:basa_capstone/viewmodels/nla_report_viewmodel.dart';
import 'package:basa_capstone/viewmodels/phil_iri_viewmodel.dart';
import 'package:basa_capstone/viewmodels/round_calendar_viewmodel.dart';
import 'package:basa_capstone/viewmodels/srp_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_online_auth.dart';

class _Lines implements Logger {
  final lines = <String>[];
  @override
  void log(String source, String message) => lines.add(message);
}

class _Calendar implements AssessmentCalendarRepository {
  final bool failing;
  _Calendar({this.failing = false});
  @override
  Future<CalendarWindow> save(CalendarWindow w) async => CalendarWindow(
      id: 9,
      schoolId: w.schoolId,
      schoolYear: w.schoolYear,
      instrument: w.instrument,
      round: w.round,
      opensOn: w.opensOn,
      closesOn: w.closesOn);
  @override
  Future<CalendarWindow> upsertWithId(CalendarWindow w) async {
    if (failing) throw Exception('locked db');
    return w;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SrpClasses implements SrpClassRepository {
  final bool failing;
  _SrpClasses({this.failing = false});
  @override
  Future<List<SrpClass>> classesFor(int schoolId, String schoolYear) async =>
      [SrpClass(id: 5, schoolId: schoolId, schoolYear: schoolYear, assessedGrade: 4, className: 'SRP A')];
  @override
  Future<void> deleteClass(int id) async {}
  @override
  Future<void> removeMirroredClass(int id) async {
    if (failing) throw Exception('locked db');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoReports implements NlaReportViewModel {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoPhilIri implements PhilIriViewModel {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoStudents implements StudentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoUsers implements UserRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoSections implements SectionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SrpViewModel _srp(_SrpClasses local, Logger logger) => SrpViewModel(
      reports: _NoReports(),
      students: _NoStudents(),
      philIri: _NoPhilIri(),
      auth: FakeOnlineAuth(UserRole.coordinator),
      local: local,
      cloud: (_) => _SrpClasses(),
      users: _NoUsers(),
      sections: _NoSections(),
      logger: logger,
    );

void main() {
  test('defaults are the srp_rules constants', () {
    final vm = _srp(_SrpClasses(), _Lines());
    expect(vm.defaultPerSection, srpDefaultPerSection);
    expect(vm.defaultClassSize, srpDefaultClassSize);
  });

  test('SrpViewModel mirror warning has no exception text', () async {
    final log = _Lines();
    final vm = _srp(_SrpClasses(failing: true), log);

    await vm.clearClasses(schoolId: 1, schoolYear: '2026-2027');

    expect(vm.lastMirrorWarning,
        'The SRP classes were changed online, but the copy on this device was not updated. Download the latest data (pull-cloud).');
    expect(log.lines.any((l) => l.contains('locked db')), isTrue);
  });

  test('roundLabel of mosy1 is MOSY #1', () {
    const w = CalendarWindow(
        schoolYear: '2026-2027', instrument: CalendarInstrument.philIri, round: 'mosy1', opensOn: '2026-11-02', closesOn: '2026-11-20');
    expect(w.roundLabel, 'MOSY #1');
  });

  test('RoundCalendarViewModel mirror warning has no exception text', () async {
    final log = _Lines();
    final vm = RoundCalendarViewModel(
        auth: FakeOnlineAuth(UserRole.admin), local: _Calendar(failing: true), cloud: (_) => _Calendar(), logger: log);

    await vm.setWindow(1, '2026-2027', CalendarInstrument.philIri, 'bosy', DateTime(2026, 6, 15), DateTime(2026, 7, 3));

    expect(vm.lastMirrorWarning, 'The calendar was changed online, but the copy on this device was not updated. Download the latest data (pull-cloud).');
    expect(log.lines.any((l) => l.contains('locked db')), isTrue);
  });
}
