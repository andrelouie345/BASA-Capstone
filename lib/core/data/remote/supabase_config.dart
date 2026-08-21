// lib/core/data/remote/supabase_config.dart
class SupabaseConfig {
  final String url;
  final String anonKey;
  const SupabaseConfig({required this.url, required this.anonKey});

  factory SupabaseConfig.cloud() => const SupabaseConfig(
        url: 'https://YOUR-PROJECT.supabase.co',
        anonKey: 'YOUR-CLOUD-ANON-KEY',
      );

  /// Self-hosted Supabase on a school PC, reachable over WiFi/LAN.
  /// Point [host] at that machine's LAN IP.
  factory SupabaseConfig.lan({String host = '192.168.1.100', String port = '8000'}) =>
      SupabaseConfig(url: 'http://$host:$port', anonKey: 'YOUR-LAN-ANON-KEY');
}