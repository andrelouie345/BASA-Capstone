// lib/core/data/remote/supabase_config.dart
import 'dart:convert';
import 'dart:io';

class SupabaseProfile {
  String url;
  String anonKey;
  SupabaseProfile({required this.url, required this.anonKey});

  Map<String, Object?> toMap() => {'url': url, 'anonKey': anonKey};
  factory SupabaseProfile.fromMap(Map<String, Object?> m) => SupabaseProfile(
        url: m['url'] as String? ?? '',
        anonKey: m['anonKey'] as String? ?? '',
      );
}

/// Holds both the cloud and LAN/self-hosted Supabase profiles.
/// Editable at runtime via console commands, persisted to a JSON file
/// so you don't lose config between `flutter run`s or console restarts.
class SupabaseConfigStore {
  SupabaseProfile cloud;
  SupabaseProfile lan;
  final String _configPath;

  SupabaseConfigStore._(this.cloud, this.lan, this._configPath);

  static Future<SupabaseConfigStore> load(String directory) async {
    final path = '$directory/supabase_config.json';
    final file = File(path);

    if (await file.exists()) {
      final data = jsonDecode(await file.readAsString()) as Map<String, Object?>;
      return SupabaseConfigStore._(
        SupabaseProfile.fromMap(data['cloud'] as Map<String, Object?>),
        SupabaseProfile.fromMap(data['lan'] as Map<String, Object?>),
        path,
      );
    }

    // No file yet: start from build-time defaults (empty unless the build
    // passes --define / --dart-define BASA_CLOUD_URL=... etc.). Nothing is
    // hardcoded in source; config-set-* commands fill in the rest.
    final store = SupabaseConfigStore._(
      SupabaseProfile(url: _cloudUrl, anonKey: _cloudKey),
      SupabaseProfile(url: _lanUrl, anonKey: _lanKey),
      path,
    );
    await store._save();
    return store;
  }

  static const _cloudUrl = String.fromEnvironment('BASA_CLOUD_URL');
  static const _cloudKey = String.fromEnvironment('BASA_CLOUD_KEY');
  static const _lanUrl = String.fromEnvironment('BASA_LAN_URL');
  static const _lanKey = String.fromEnvironment('BASA_LAN_KEY');

  Future<void> _save() async {
    final file = File(_configPath);
    await file.writeAsString(jsonEncode({
      'cloud': cloud.toMap(),
      'lan': lan.toMap(),
    }));
  }

  Future<void> setCloud({String? url, String? anonKey}) async {
    if (url != null) cloud.url = url;
    if (anonKey != null) cloud.anonKey = anonKey;
    await _save();
  }

  Future<void> setLan({String? url, String? anonKey}) async {
    if (url != null) lan.url = url;
    if (anonKey != null) lan.anonKey = anonKey;
    await _save();
  }
}