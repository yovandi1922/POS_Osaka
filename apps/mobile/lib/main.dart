// apps/mobile/lib/main.dart
// Entry point aplikasi kasir. Jalankan: flutter run --dart-define-from-file=env.json
import 'package:coffee_core/coffee_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'config.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'state/auth_controller.dart';
import 'state/cart.dart';
import 'state/tab_nav.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (AppConfig.missing.isNotEmpty) {
    runApp(_ConfigErrorApp(missing: AppConfig.missing));
    return;
  }

  await sb.Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
  final client = sb.Supabase.instance.client;
  final repo = CoffeeRepository(client);

  runApp(
    MultiProvider(
      providers: [
        Provider<CoffeeRepository>.value(value: repo),
        ChangeNotifierProvider(create: (_) => AuthController(client, repo)),
        ChangeNotifierProvider(create: (_) => Cart()),
        ChangeNotifierProvider(create: (_) => TabNav()),
        Provider<CoffeeApi>(
          create: (_) => CoffeeApi(
            baseUrl: AppConfig.apiBaseUrl,
            accessToken: () => client.auth.currentSession?.accessToken,
          ),
        ),
      ],
      child: const CoffeePosApp(),
    ),
  );
}

class CoffeePosApp extends StatelessWidget {
  const CoffeePosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Coffee POS',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const _AuthGate(),
    );
  }
}

/// Cek sesi → LoginScreen atau MainShell (tab Home, Kasir, Stok, Pengeluaran, Laporan, Asisten).
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    if (auth.initializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return auth.isSignedIn ? const MainShell() : const LoginScreen();
  }
}

class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp({required this.missing});

  final List<String> missing;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Konfigurasi belum lengkap: ${missing.join(', ')}.\n\n'
              'Salin env.example.json menjadi env.json, isi nilainya, lalu jalankan:\n'
              'flutter run --dart-define-from-file=env.json',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
