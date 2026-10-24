// lib/ui/admin/admin_scope.dart
// Hands the admin-only ViewModels to admin-build screens. Admin build only:
// everything under lib/ui/admin/ is unreachable from the tutor entry points
// (tool/check_tutor_imports.dart). lib/main.dart puts it above BasaApp:
//   final admin = AdminScope.of(context);
//   await admin.users.loadAll();
import 'package:flutter/widgets.dart';

import '../../viewmodels/admin_viewmodels.dart';

class AdminScope extends InheritedWidget {
  final AdminViewModels vms;

  const AdminScope({super.key, required this.vms, required super.child});

  static AdminViewModels of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AdminScope>();
    if (scope == null) throw StateError('No AdminScope above this widget (admin build only; lib/main.dart puts it at the root).');
    return scope.vms;
  }

  @override
  bool updateShouldNotify(AdminScope oldWidget) => !identical(vms, oldWidget.vms);
}
