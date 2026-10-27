// lib/ui/admin/crla_threshold_editing.dart
// The CRLA thresholds screen's admin part: change cut-offs (school, or the
// region for a superadmin), go back to the region's values, and recompute
// the profiles of saved attempts. Admin build only.
import 'package:flutter/material.dart';

import '../../viewmodels/crla_threshold_viewmodel.dart';
import '../common/screen_kit.dart';
import '../common/signed_in_user.dart';
import '../crla/crla_thresholds_screen.dart';

class AdminCrlaThresholdsEditor extends CrlaThresholdsEditor {
  const AdminCrlaThresholdsEditor();

  @override
  bool canEdit(BuildContext context) {
    final me = vmsOf(context).auth.currentUser;
    return me != null && isAdminOrCoordinator(me);
  }

  @override
  Future<bool> edit(BuildContext context, int? schoolId, CrlaThresholdLayers layers) async {
    final current = layers.effective.toMap();
    final f = await askFields(
      context,
      title: schoolId == null ? 'Region CRLA thresholds' : 'School CRLA thresholds',
      note: 'Whole numbers; true/false for the yes/no rows. Only changed values are saved.',
      fields: [for (final e in current.entries) FieldSpec(e.key, thresholdLabel(e.key), initial: '${e.value}')],
    );
    if (f == null || !context.mounted) return false;
    final changes = <String, Object?>{};
    for (final e in f.entries) {
      final old = current[e.key];
      if (e.value == '$old') continue;
      final Object? v = old is bool ? e.value.toLowerCase() == 'true' : int.tryParse(e.value);
      if (v == null) {
        showNote(context, '${thresholdLabel(e.key)}: "${e.value}" is not a valid value.');
        return false;
      }
      changes[e.key] = v;
    }
    if (changes.isEmpty) return false;
    final vm = vmsOf(context).crlaThresholds;
    final saved = await runAction(context, () => vm.saveThresholds(schoolId: schoolId, changes: changes),
        done: 'Thresholds saved. Profiles of new attempts use them.', where: 'CrlaThresholds');
    if (vm.lastMirrorWarning != null && context.mounted) showNote(context, vm.lastMirrorWarning!);
    return saved != null;
  }

  @override
  Future<bool> reset(BuildContext context, int schoolId) async {
    if (!await confirm(context, title: "Use the region's thresholds?", body: "The school's own cut-offs are removed.", action: 'Reset')) {
      return false;
    }
    if (!context.mounted) return false;
    final vm = vmsOf(context).crlaThresholds;
    return runStep(context, () => vm.resetSchoolThresholds(schoolId), done: 'School thresholds removed.', where: 'CrlaThresholds');
  }
}
