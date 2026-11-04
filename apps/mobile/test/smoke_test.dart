// apps/mobile/test/smoke_test.dart
// Smoke test UI: semua tab & layar render tanpa exception layout.
// Request jaringan di flutter_test selalu gagal (HTTP 400) → layar harus menampilkan state error, bukan crash.
import 'package:coffee_core/coffee_core.dart';
import 'package:coffee_pos_mobile/screens/checkout_screen.dart';
import 'package:coffee_pos_mobile/screens/login_screen.dart';
import 'package:coffee_pos_mobile/screens/main_shell.dart';
import 'package:coffee_pos_mobile/state/auth_controller.dart';
import 'package:coffee_pos_mobile/state/cart.dart';
import 'package:coffee_pos_mobile/state/tab_nav.dart';
import 'package:coffee_pos_mobile/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

Widget _app(WidgetTester tester, Widget home, {Cart? cart}) {
  final client = sb.SupabaseClient(
    'http://localhost:54321',
    'test-anon-key',
    authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
  );
  final repo = CoffeeRepository(client);
  return MultiProvider(
    providers: [
      Provider<CoffeeRepository>.value(value: repo),
      ChangeNotifierProvider(create: (_) => AuthController(client, repo)),
      ChangeNotifierProvider.value(value: cart ?? Cart()),
      ChangeNotifierProvider(create: (_) => TabNav()),
      Provider<CoffeeApi>(create: (_) => CoffeeApi(baseUrl: 'http://localhost:3000', accessToken: () => null)),
    ],
    child: MaterialApp(theme: buildTheme(), home: home),
  );
}

void main() {
  testWidgets('login screen render', (tester) async {
    await tester.pumpWidget(_app(tester, const LoginScreen()));
    expect(find.text('Coffee POS'), findsOneWidget);
    await tester.tap(find.text('Masuk'));
    await tester.pump();
    expect(find.text('Email dan password wajib diisi.'), findsOneWidget);
  });

  testWidgets('semua tab main shell render', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(tester, const MainShell()));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('AKSI CEPAT'), findsOneWidget);

    for (final label in ['Kasir', 'Stok', 'Biaya', 'Laporan', 'Asisten', 'Beranda']) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull, reason: 'tab $label');
    }
  });

  testWidgets('checkout menghitung kembalian', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    final cart = Cart()
      ..add(const MenuItem(id: 'm1', name: 'Kopi Susu Gula Aren', price: 22000, cost: 8000, isActive: true))
      ..add(const MenuItem(id: 'm1', name: 'Kopi Susu Gula Aren', price: 22000, cost: 8000, isActive: true));
    await tester.pumpWidget(_app(tester, const CheckoutScreen(), cart: cart));
    await tester.pump();
    expect(find.text('Rp 44.000'), findsWidgets);

    await tester.enterText(find.byType(TextField), '50000');
    await tester.pump();
    expect(find.text('Rp 6.000'), findsOneWidget);

    await tester.tap(find.text('QRIS'));
    await tester.pump();
    expect(find.textContaining('Pastikan pembayaran QRIS'), findsOneWidget);
  });
}
