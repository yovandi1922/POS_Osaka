// apps/admin/lib/config.dart
// Konfigurasi dibaca saat build: flutter run -d chrome --dart-define-from-file=env.json
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Base URL backend apps/api, mis. `https://coffee-pos-api.vercel.app` (dev: `http://localhost:3000`)
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static List<String> get missing => [
        if (supabaseUrl.isEmpty) 'SUPABASE_URL',
        if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
      ];
}
