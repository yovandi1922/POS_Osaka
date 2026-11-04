// apps/admin/lib/main.dart
// Entry point web admin. Jalankan: flutter run -d chrome --dart-define-from-file=env.json
import 'package:coffee_core/coffee_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import 'config.dart';
import 'router.dart';
import 'state/admin_session.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (AppConfig.missing.isNotEmpty) {
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Text(
            'Konfigurasi belum lengkap: ${AppConfig.missing.join(', ')}.\n'
            'Salin env.example.json → env.json lalu jalankan dengan --dart-define-from-file=env.json',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ));
    return;
  }

  await sb.Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
  final client = sb.Supabase.instance.client;
  final repo = CoffeeRepository(client);
  final session = AdminSession(client, repo);

  runApp(
    MultiProvider(
      providers: [
        Provider<CoffeeRepository>.value(value: repo),
        ChangeNotifierProvider<AdminSession>.value(value: session),
        Provider<CoffeeApi>(
          create: (_) => CoffeeApi(baseUrl: AppConfig.apiBaseUrl, accessToken: () => client.auth.currentSession?.accessToken),
        ),
      ],
      child: AdminApp(router: buildRouter(session)),
    ),
  );
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key, required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Coffee POS Admin',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: router,
    );
  }
}
