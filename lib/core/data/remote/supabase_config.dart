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

    // Sensible empty defaults — commands below fill these in.
    final store = SupabaseConfigStore._(
      SupabaseProfile(url: 'https://ssgewslamdlbllqcgkrr.supabase.co', anonKey: 'sb_publishable_7f9og99jvpbMyroXyUCDsQ_zEGPtlL3'),
      SupabaseProfile(url: 'http://192.168.1.100:8000', anonKey: ''),
      path,
    );
    await store._save();
    return store;
  }

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