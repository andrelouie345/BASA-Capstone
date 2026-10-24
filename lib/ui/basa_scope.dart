// lib/ui/basa_scope.dart
// Hands the ViewModels to every screen (both builds). BasaApp puts it above
// MaterialApp, so every route sees it:
//   final vms = BasaScope.of(context);
//   final result = await vms.crla.getResult(id);
// ViewModels are request/response (no ChangeNotifier, no stream): the scope
// never changes after start-up, and screens keep their own loading / error
// state. Admin-only ViewModels: ui/admin/admin_scope.dart.
import 'package:flutter/widgets.dart';

import '../viewmodels/app_viewmodels.dart';

class BasaScope extends InheritedWidget {
  final AppViewModels vms;

  const BasaScope({super.key, required this.vms, required super.child});

  static AppViewModels of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<BasaScope>();
    if (scope == null) throw StateError('No BasaScope above this widget (BasaApp puts it at the root).');
    return scope.vms;
  }

  @override
  bool updateShouldNotify(BasaScope oldWidget) => !identical(vms, oldWidget.vms);
}
