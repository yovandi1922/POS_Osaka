// apps/mobile/lib/config.dart
// Konfigurasi dibaca saat build: flutter run --dart-define-from-file=env.json
import 'package:flutter/foundation.dart';

class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Nilai mentah dari env.json, mis. https://coffee-pos-api.vercel.app
  /// (saat dev di HP fisik: `http://IP-LAN-PC:3000`; emulator Android: `http://10.0.2.2:3000`)
  static const _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Base URL backend apps/api.
  /// Dev di browser (halaman dibuka dari localhost) + API_BASE_URL berupa IP LAN →
  /// pakai localhost, supaya tidak putus tiap kali IP Wi-Fi PC berganti.
  static String get apiBaseUrl {
    if (!kIsWeb || _apiBaseUrl.isEmpty) return _apiBaseUrl;
    final page = Uri.base.host;
    if (page != 'localhost' && page != '127.0.0.1') return _apiBaseUrl;
    final api = Uri.tryParse(_apiBaseUrl);
    if (api == null || !_isPrivateIp(api.host)) return _apiBaseUrl;
    return api.replace(host: 'localhost').toString().replaceAll(RegExp(r'/$'), '');
  }

  static bool _isPrivateIp(String host) {
    final p = host.split('.').map(int.tryParse).toList();
    if (p.length != 4 || p.any((n) => n == null)) return false;
    final a = p[0]!, b = p[1]!;
    return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
  }

  static List<String> get missing => [
        if (supabaseUrl.isEmpty) 'SUPABASE_URL',
        if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
      ];
}
