// The six Phil-IRI value switches (spec 2026-11-14 value sources D1-D3):
// report_settings keys values_<list> = "carried" | "actual", read school ->
// region -> default (ranking actual, the rest carried). Anything else stored
// reads as the list's default.
import 'package:basa_capstone/core/models/report_setting.dart';
import 'package:basa_capstone/core/models/user_role.dart';
import 'package:basa_capstone/core/repositories/report_setting_repository.dart';
import 'package:basa_capstone/core/services/auth_messages.dart';
import 'package:basa_capstone/viewmodels/report_settings_viewmodel.dart';
import 'package:basa_capstone/viewmodels/viewmodel_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase/supabase.dart' show SupabaseClient;

import '../helpers/fake_online_auth.dart';

Matcher _refused(String message) =>
    throwsA(isA<ViewModelException>().having((e) => e.message, 'message', message));

/// Signed in, but offline: no server session.
class _OfflineAuth extends FakeOnlineAuth {
  _OfflineAuth() : super(UserRole.coordinator);
  @override
  SupabaseClient? get client => null;
  @override
  String? requireOnlineSession({bool allowPendingPasswordChange = false}) => needsOnlineSignInMessage;
}

class _Settings implements ReportSettingRepository {
  ReportSetting? region;
  final schools = <int, ReportSetting>{};
  @override
  Future<ReportSetting?> getRegion() async => region;
  @override
  Future<ReportSetting?> getForSchool(int schoolId) async => schools[schoolId];
  @override
  Future<ReportSetting> save(int? schoolId, Map<String, Object?> settings) async {
    final s = ReportSetting(id: schoolId ?? 0, schoolId: schoolId, settings: settings);
    schoolId == null ? region = s : schools[schoolId] = s;
    return s;
  }

  @override
  Future<ReportSetting> upsertWithId(ReportSetting setting) async => save(setting.schoolId, setting.settings);
  @override
  Future<void> deleteForSchool(int schoolId) async => schools.remove(schoolId);
  @override
  Future<void> removeMirroredForSchool(int schoolId) async => schools.remove(schoolId);
}

void main() {
  late _Settings local, cloud;
  ReportSettingsViewModel vmFor(FakeOnlineAuth auth) =>
      ReportSettingsViewModel(auth: auth, local: local, cloud: (_) => cloud);

  setUp(() {
    local = _Settings();
    cloud = _Settings();
  });

  test('the six keys, their console names and defaults', () {
    expect({for (final l in PhilIriValueList.values) l.key: (l.cliName, l.defaultValue)}, {
      'values_aral': ('aral', PhilIriValues.carried),
      'values_bosy_masterlist': ('bosy-masterlist', PhilIriValues.carried),
      'values_form2b': ('form2b', PhilIriValues.carried),
      'values_srp': ('srp', PhilIriValues.carried),
      'values_learner_pages': ('learner-pages', PhilIriValues.carried),
      'values_ranking': ('ranking', PhilIriValues.actual),
    });
    expect(philIriValuesLabel(PhilIriValues.carried), 'Values: carried (best so far)');
    expect(philIriValuesLabel(PhilIriValues.actual), "Values: actual (each round's own reading)");
  });

  test('defaults: no rows -> ranking actual, the rest carried', () async {
    for (final s in [ReportSettings.fromMap({}), const ReportSettings()]) {
      for (final l in PhilIriValueList.values) {
        expect(s.valueSource(l), l.defaultValue, reason: l.key);
      }
      expect(s.valueSources.keys.toSet(), PhilIriValueList.values.toSet());
    }
    final layers = await vmFor(FakeOnlineAuth(UserRole.coordinator)).valueSourceLayers(1);
    for (final l in PhilIriValueList.values) {
      expect((layers[l]!.region, layers[l]!.school, layers[l]!.effective), (null, null, l.defaultValue));
    }
  });

  test('school over region; a school row without the key takes the region value', () async {
    local.region = ReportSetting(id: 1, settings: {'values_srp': 'actual'});
    local.schools[1] = ReportSetting(id: 2, schoolId: 1, settings: {'values_srp': 'carried'});
    final vm = vmFor(FakeOnlineAuth(UserRole.coordinator));
    final l = (await vm.valueSourceLayers(1))[PhilIriValueList.srp]!;
    expect((l.region, l.school, l.effective), (PhilIriValues.actual, PhilIriValues.carried, PhilIriValues.carried));

    local.schools[1] = ReportSetting(id: 2, schoolId: 1, settings: {'done_threshold': 0.9});
    final l2 = (await vm.valueSourceLayers(1))[PhilIriValueList.srp]!;
    expect((l2.region, l2.school, l2.effective), (PhilIriValues.actual, null, PhilIriValues.actual));
    expect((await vm.effective(1)).valueSource(PhilIriValueList.srp), PhilIriValues.actual);

    // The region view (schoolId null) shows no school layer.
    final r = (await vm.valueSourceLayers(null))[PhilIriValueList.srp]!;
    expect((r.region, r.school, r.effective), (PhilIriValues.actual, null, PhilIriValues.actual));
  });

  test('an unknown stored value reads as the default', () async {
    for (final bad in <Object?>['Actual', true, 1, null, 'actual ']) {
      expect(ReportSettings.fromMap({'values_aral': bad}).valueSource(PhilIriValueList.aral), PhilIriValues.carried,
          reason: '$bad');
      expect(ReportSettings.fromMap({'values_ranking': bad == 'Actual' ? 'Carried' : bad})
          .valueSource(PhilIriValueList.ranking), PhilIriValues.actual, reason: '$bad');
    }
    local.schools[1] = ReportSetting(id: 2, schoolId: 1, settings: {'values_aral': 'Actual'});
    final l = (await vmFor(FakeOnlineAuth(UserRole.coordinator)).valueSourceLayers(1))[PhilIriValueList.aral]!;
    expect((l.school, l.effective), (null, PhilIriValues.carried));
  });

  test('setValueSource saves the string, keeps the other keys and mirrors it', () async {
    cloud.schools[1] = ReportSetting(id: 2, schoolId: 1, settings: {'done_threshold': 0.9});
    final vm = vmFor(FakeOnlineAuth(UserRole.coordinator));
    final saved = await vm.setValueSource(1, PhilIriValueList.ranking, PhilIriValues.carried);
    expect(saved.settings, {'done_threshold': 0.9, 'values_ranking': 'carried'});
    expect(local.schools[1]!.settings['values_ranking'], 'carried');
    final l = (await vm.valueSourceLayers(1))[PhilIriValueList.ranking]!;
    expect((l.school, l.effective), (PhilIriValues.carried, PhilIriValues.carried));

    await vmFor(FakeOnlineAuth(UserRole.admin, schoolId: null))
        .setValueSource(null, PhilIriValueList.form2b, PhilIriValues.actual);
    expect(cloud.region!.settings, {'values_form2b': 'actual'});
  });

  test('setValueSource refuses offline, a tutor, another school and a school admin on the region row', () async {
    await expectLater(_vm(_OfflineAuth()).setValueSource(1, PhilIriValueList.aral, PhilIriValues.actual),
        _refused(needsOnlineSignInMessage));
    await expectLater(
        vmFor(FakeOnlineAuth(UserRole.tutor)).setValueSource(1, PhilIriValueList.aral, PhilIriValues.actual),
        _refused('Forbidden: only an admin or coordinator sets the report settings.'));
    await expectLater(
        vmFor(FakeOnlineAuth(UserRole.coordinator)).setValueSource(2, PhilIriValueList.aral, PhilIriValues.actual),
        _refused("Forbidden: you can only set your own school's report settings."));
    await expectLater(
        vmFor(FakeOnlineAuth(UserRole.admin)).setValueSource(null, PhilIriValueList.aral, PhilIriValues.actual),
        _refused('Forbidden: only the superadmin sets the region-wide report settings.'));
    expect(cloud.region, isNull);
    expect(cloud.schools, isEmpty);
  });

  test('valueSourceLayers refuses while signed out', () async {
    await expectLater(vmFor(FakeOnlineAuth.signedOut()).valueSourceLayers(1), _refused(notSignedInMessage));
  });
}

ReportSettingsViewModel _vm(FakeOnlineAuth auth) =>
    ReportSettingsViewModel(auth: auth, local: _Settings(), cloud: (_) => _Settings());
