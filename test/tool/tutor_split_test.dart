// Which files count as admin for tool/check_tutor_imports.dart: the screens'
// ViewModel bundles are split so a tutor screen can't reach admin ViewModels.
import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_tutor_imports.dart';
import '../../tool/import_walk.dart';

void main() {
  test('admin ViewModel bundle and admin screens are admin files', () {
    expect(isAdminFile('viewmodels/admin_viewmodels.dart'), isTrue);
    expect(isAdminFile('ui/admin/admin_scope.dart'), isTrue);
    expect(isAdminFile('ui/admin/users/user_list_screen.dart'), isTrue);
  });

  test('shared bundle and scope are not admin files', () {
    expect(isAdminFile('viewmodels/app_viewmodels.dart'), isFalse);
    expect(isAdminFile('ui/basa_scope.dart'), isFalse);
    expect(isAdminFile('ui/mobile/crla_screen.dart'), isFalse);
  });

  test('the tutor entries reach no admin file (real tree)', () {
    final v = findForbiddenImports(
      packageRoot: '.',
      packageName: 'basa_capstone',
      entries: const ['main_tutor.dart', 'console/main_tutor.dart'],
      isForbidden: isAdminFile,
    );
    expect(v, isEmpty, reason: v.join('\n'));
  });
}
