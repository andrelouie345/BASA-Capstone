// lib/viewmodels/server_config_viewmodel.dart
// The cloud and LAN server settings (URL + anon key) a setup screen shows
// and edits, persisted in <data dir>/supabase_config.json. Keys are shown
// masked. Works before sign-in (a fresh device needs it to sign in at all).
import '../core/console/logger.dart';
import '../core/data/remote/supabase_config.dart';

/// The settings as a screen shows them; keys masked.
class ServerConfigView {
  final String cloudUrl; // '' when not set
  final String cloudKeyMasked;
  final String lanUrl;
  final String lanKeyMasked;

  const ServerConfigView({
    required this.cloudUrl,
    required this.cloudKeyMasked,
    required this.lanUrl,
    required this.lanKeyMasked,
  });
}

class ServerConfigViewModel {
  final ScopedLogger _log;
  final SupabaseConfigStore _config;

  ServerConfigViewModel({required SupabaseConfigStore config, Logger? logger})
      : _config = config,
        _log = ScopedLogger(logger, 'ServerConfigViewModel');

  ServerConfigView show() => ServerConfigView(
        cloudUrl: _config.cloud.url,
        cloudKeyMasked: _mask(_config.cloud.anonKey),
        lanUrl: _config.lan.url,
        lanKeyMasked: _mask(_config.lan.anonKey),
      );

  /// Changes the given cloud values; null leaves a value as it is.
  Future<void> setCloud({String? url, String? anonKey}) async {
    _log('setCloud(url: ${url ?? '-'}, key: ${anonKey == null ? '-' : 'new'})');
    await _config.setCloud(url: url, anonKey: anonKey);
  }

  /// Changes the given LAN values; null leaves a value as it is.
  Future<void> setLan({String? url, String? anonKey}) async {
    _log('setLan(url: ${url ?? '-'}, key: ${anonKey == null ? '-' : 'new'})');
    await _config.setLan(url: url, anonKey: anonKey);
  }

  /// '(not set)', stars for a short key, else its first and last 4 characters.
  static String _mask(String key) {
    if (key.isEmpty) return '(not set)';
    if (key.length <= 8) return '*' * key.length;
    return '${key.substring(0, 4)}...${key.substring(key.length - 4)}';
  }
}
