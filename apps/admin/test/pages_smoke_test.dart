// apps/admin/test/pages_smoke_test.dart
// Smoke test: setiap halaman admin render di layar desktop & ponsel tanpa exception layout.
// Request jaringan di flutter_test selalu gagal → halaman harus menampilkan state error, bukan crash.
import 'package:coffee_core/coffee_core.dart';
import 'package:coffee_pos_admin/pages/chat_page.dart';
import 'package:coffee_pos_admin/pages/dashboard_page.dart';
import 'package:coffee_pos_admin/pages/expenses_page.dart';
import 'package:coffee_pos_admin/pages/ingredients_page.dart';
import 'package:coffee_pos_admin/pages/login_page.dart';
import 'package:coffee_pos_admin/pages/menu_page.dart';
import 'package:coffee_pos_admin/pages/predictions_page.dart';
import 'package:coffee_pos_admin/pages/reports_page.dart';
import 'package:coffee_pos_admin/pages/transactions_page.dart';
import 'package:coffee_pos_admin/pages/users_page.dart';
import 'package:coffee_pos_admin/state/admin_session.dart';
import 'package:coffee_pos_admin/theme.dart';
import 'package:coffee_pos_admin/widgets/charts.dart';
import 'package:coffee_pos_admin/widgets/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

Widget _wrap(Widget child) {
  final client = sb.SupabaseClient(
    'http://localhost:54321',
    'test-anon-key',
    authOptions: const sb.AuthClientOptions(autoRefreshToken: false),
  );
  final repo = CoffeeRepository(client);
  return MultiProvider(
    providers: [
      Provider<CoffeeRepository>.value(value: repo),
      ChangeNotifierProvider(create: (_) => AdminSession(client, repo)),
      Provider<CoffeeApi>(create: (_) => CoffeeApi(baseUrl: 'http://localhost:3000', accessToken: () => null)),
    ],
    child: MaterialApp(theme: buildTheme(), home: AdminShell(location: '/dashboard', child: Material(child: child))),
  );
}

void main() {
  final pages = <String, Widget Function()>{
    'dashboard': () => const DashboardPage(),
    'chat': () => const ChatPage(),
    'transactions': () => const TransactionsPage(),
    'menu': () => const MenuPage(),
    'ingredients': () => const IngredientsPage(),
    'expenses': () => const ExpensesPage(),
    'reports': () => const ReportsPage(),
    'predictions': () => const PredictionsPage(),
    'users': () => const UsersPage(),
  };

  for (final size in const [Size(1440, 900), Size(390, 844)]) {
    for (final entry in pages.entries) {
      testWidgets('${entry.key} @ ${size.width.toInt()}px', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_wrap(entry.value()));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('login page render', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = sb.SupabaseClient('http://localhost:54321', 'k', authOptions: const sb.AuthClientOptions(autoRefreshToken: false));
    final repo = CoffeeRepository(client);
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => AdminSession(client, repo),
      child: MaterialApp(theme: buildTheme(), home: const LoginPage()),
    ));
    await tester.tap(find.text('Masuk'));
    await tester.pump();
    expect(find.text('Email dan password wajib diisi.'), findsOneWidget);
  });

  testWidgets('grafik render dengan data', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var day = '2026-09-01';
    final daily = <RevenueByDay>[];
    for (var i = 0; i < 30; i++) {
      daily.add(RevenueByDay(day: day, revenue: 1000000 + (i % 7) * 150000, txCount: 20 + i % 5));
      day = addDays(day, 1);
    }
    final history = [for (final d in daily) DailyRevenue(d.day, d.revenue)];
    final prediction = predictRevenue(history, daysAhead: 14) as PredictSuccess;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: ListView(children: [
          RevenueTrendChart(data: daily),
          RevenueExpenseChart(data: [for (final d in daily) RevenueExpensePoint(d.day, d.revenue, d.revenue * 0.3)]),
          const CategoryBars(rows: [MapEntry('Coffee', 5000000), MapEntry('Snack', 1200000)], color: AppColors.revenue, total: 6200000),
          PredictionChart(actual: history.sublist(9), predictions: prediction.predictions),
        ]),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.text('Coffee'), findsOneWidget);
  });
}
