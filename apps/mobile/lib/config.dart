// apps/mobile/lib/config.dart
// Konfigurasi dibaca saat build: flutter run --dart-define-from-file=env.json
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Base URL backend apps/api, mis. https://coffee-pos-api.vercel.app
  /// (saat dev di HP fisik: `http://IP-LAN-PC:3000`; emulator Android: `http://10.0.2.2:3000`)
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static List<String> get missing => [
        if (supabaseUrl.isEmpty) 'SUPABASE_URL',
        if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
      ];
}
