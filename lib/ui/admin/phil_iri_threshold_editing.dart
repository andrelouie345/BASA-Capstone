// lib/ui/admin/phil_iri_threshold_editing.dart
// The Phil-IRI thresholds screen's admin part: change cut-offs (school, or
// the region for a superadmin) and go back to the region's values. Admin
// build only.
import 'package:flutter/material.dart';

import '../../viewmodels/phil_iri_content_viewmodel.dart';
import '../common/screen_kit.dart';
import '../common/signed_in_user.dart';
import '../phil_iri/phil_iri_thresholds_screen.dart';
import 'threshold_fields.dart';

class AdminPhilIriThresholdsEditor extends PhilIriThresholdsEditor {
  const AdminPhilIriThresholdsEditor();

  @override
  bool canEdit(BuildContext context) {
    final me = vmsOf(context).auth.currentUser;
    return me != null && isAdminOrCoordinator(me);
  }

  @override
  Future<bool> edit(BuildContext context, int? schoolId, PhilIriThresholdLayers layers) async {
    final changes = await askThresholdChanges(context,
        title: schoolId == null ? 'Region Phil-IRI thresholds' : 'School Phil-IRI thresholds',
        current: layers.effective.toMap());
    if (changes == null || changes.isEmpty || !context.mounted) return false;
    final vm = vmsOf(context).philIriContent;
    final saved = await runAction(context, () => vm.saveThresholds(schoolId: schoolId, changes: changes),
        done: 'Thresholds saved.', where: 'PhilIriThresholds');
    if (vm.lastMirrorWarning != null && context.mounted) showNote(context, vm.lastMirrorWarning!);
    return saved != null;
  }

  @override
  Future<bool> reset(BuildContext context, int schoolId) async {
    if (!await confirm(context,
        title: "Use the region's thresholds?", body: "The school's own cut-offs are removed.", action: 'Reset')) {
      return false;
    }
    if (!context.mounted) return false;
    final vm = vmsOf(context).philIriContent;
    return runStep(context, () => vm.resetSchoolThresholds(schoolId),
        done: 'School thresholds removed.', where: 'PhilIriThresholds');
  }
}
