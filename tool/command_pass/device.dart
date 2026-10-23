// Devices of the command pass: one data folder per device, wired like the
// tutor or admin console. LocalDatabase is a process-wide singleton, so only
// one device is open at a time (plan D2).
import 'dart:io';

import 'package:basa_capstone/core/console/console_command.dart';
import 'package:basa_capstone/core/data/local/local_database.dart';
import 'package:basa_capstone/core/wiring/app_context.dart';
import 'package:basa_capstone/core/wiring/wire_admin.dart';
import 'package:basa_capstone/core/wiring/wire_shared.dart';
import 'package:basa_capstone/core/wiring/wire_tutor.dart';

class Device {
  final String name;
  final String build; // 'tutor' | 'admin'
  final Directory dir;
  final AppContext ctx;
  /// The account last signed in here; the runner signs it in again when it
  /// switches back to this device (sign-in lives in memory only).
  String? lastAccount;

  Device(this.name, this.build, this.dir, this.ctx, {this.lastAccount});

  ConsoleCommand? command(String name) {
    for (final c in ctx.registry.all) {
      if (c.name == name) return c;
    }
    return null;
  }
}

class DeviceManager {
  final Directory runDir;
  /// supabase_config.json copied into a new device folder (the dev cloud).
  final String? configSource;
  final Map<String, String?> _lastAccounts = {};
  Device? _open;

  DeviceManager(this.runDir, {this.configSource});

  Device? get current => _open;

  /// Opens [name], closing the device open before it. Switching to the open
  /// device keeps it as it is. A device keeps its build for the whole run.
  Future<Device> switchTo(String name, String build) async {
    final dir = Directory('${runDir.path}/devices/$name');
    final buildFile = File('${dir.path}/build.txt');
    if (buildFile.existsSync() && buildFile.readAsStringSync().trim() != build) {
      throw StateError('device "$name" is a ${buildFile.readAsStringSync().trim()} device, not $build');
    }
    final open = _open;
    if (open != null && open.name == name) return open;
    await close();

    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      final source = configSource;
      if (source != null && File(source).existsSync()) {
        File(source).copySync('${dir.path}/supabase_config.json');
      }
    }
    buildFile.writeAsStringSync(build);

    final ctx = await AppContext.open(dataDir: dir.path);
    // Same order as lib/console/main_tutor.dart and lib/console/main.dart.
    final shared = wireShared(ctx);
    final tutor = wireTutor(ctx, shared);
    if (build == 'admin') {
      final admin = await wireAdmin(ctx, shared, tutor);
      registerSharedCommands(ctx, shared);
      registerTutorCommands(ctx, shared, tutor);
      registerAdminCommands(ctx, shared, tutor, admin);
    } else {
      registerSharedCommands(ctx, shared);
      registerTutorCommands(ctx, shared, tutor);
    }
    registerDevCommands(ctx, shared);

    final device = Device(name, build, dir, ctx, lastAccount: _lastAccounts[name]);
    _open = device;
    return device;
  }

  Future<void> close() async {
    final open = _open;
    if (open == null) return;
    _lastAccounts[open.name] = open.lastAccount;
    await LocalDatabase.close();
    _open = null;
  }
}
