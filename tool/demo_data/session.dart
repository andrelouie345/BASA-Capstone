// The demo builder's devices and accounts (demo-data plan Task 5): one device
// folder per demo account under <dir>/devices/<key>, the admin build for the
// superadmin, coordinators and school admin, the tutor build for tutors (as
// in real use). Signs in online; a temporary password is replaced by a
// generated one and kept only in <dir>/accounts.json (outside the repo).
// Passwords are never printed.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:basa_capstone/core/models/user_role.dart';

import '../command_pass/device.dart';
import 'world.dart';

/// The command pass's test superadmin: only used to create demo.super.
const demoBootstrapKey = 'bootstrap';
const demoBootstrapAccounts = r'D:\0_CAPSTONE\verify\pass\accounts.json';

class DemoSession {
  final Directory dir;
  final DeviceManager _devices;
  final File _accountsFile;
  final Map<String, Map<String, dynamic>> _accounts;

  DemoSession._(this.dir, this._devices, this._accountsFile, this._accounts);

  static Future<DemoSession> open(Directory dir, {required String configPath}) async {
    dir.createSync(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}accounts.json');
    final accounts = file.existsSync()
        ? (jsonDecode(file.readAsStringSync()) as Map<String, dynamic>).cast<String, Map<String, dynamic>>()
        : <String, Map<String, dynamic>>{};
    return DemoSession._(dir, DeviceManager(dir, configSource: configPath), file, accounts);
  }

  /// The account's device, signed in as that account.
  Future<Device> as(String key) async {
    final tutor = key != demoBootstrapKey && demoAccount(key).role == UserRole.tutor;
    final dev = await _devices.switchTo(key, tutor ? 'tutor' : 'admin');
    final auth = dev.ctx.authVm;
    if (dev.lastAccount == key && auth.isSignedIn) return dev;
    if (auth.isSignedIn) await auth.signOut();
    final cred = _credential(key);
    final error = await auth.signIn(target: 'cloud', email: cred.email, password: cred.password);
    if (error != null) throw StateError('sign-in as $key failed: $error');
    if (auth.mustChangePassword) {
      final fresh = _newPassword();
      final changed = await auth.changePassword(fresh);
      if (changed != null) throw StateError('changing the temporary password of $key failed: $changed');
      await _store(key, cred.email, fresh);
    }
    dev.lastAccount = key;
    return dev;
  }

  /// Whether [key] already has a password here (created by an earlier run).
  bool hasPassword(String key) => _accounts.containsKey(key);

  /// The temporary password user creation returned; replaced at first sign-in.
  Future<void> rememberTemporary(String key, String email, String password) => _store(key, email, password);

  Future<void> close() => _devices.close();

  ({String email, String password}) _credential(String key) {
    if (key == demoBootstrapKey) {
      final s = (jsonDecode(File(demoBootstrapAccounts).readAsStringSync()) as Map<String, dynamic>)['super'];
      if (s == null) throw StateError('no "super" account in $demoBootstrapAccounts');
      return (email: s['email'] as String, password: s['password'] as String);
    }
    final a = _accounts[key];
    if (a == null) throw StateError('no password for $key in ${_accountsFile.path} (create the account first)');
    return (email: a['email'] as String, password: a['password'] as String);
  }

  Future<void> _store(String key, String email, String password) async {
    if (key == demoBootstrapKey) {
      final f = File(demoBootstrapAccounts);
      final all = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      all['super'] = {'email': email, 'password': password};
      f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(all));
      return;
    }
    _accounts[key] = {'email': email, 'password': password};
    await _accountsFile.writeAsString(const JsonEncoder.withIndent('  ').convert(_accounts));
  }

  static String _newPassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    final r = Random.secure();
    return 'Nc9!${List.generate(16, (_) => chars[r.nextInt(chars.length)]).join()}';
  }
}
