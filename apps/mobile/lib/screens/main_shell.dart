// apps/mobile/lib/screens/main_shell.dart
// Bottom navigation: Home, Kasir (nested stack POS → Checkout), Stok, Pengeluaran, Laporan, Asisten.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/cart.dart';
import '../state/tab_nav.dart';
import 'chat_screen.dart';
import 'expense_screen.dart';
import 'home_screen.dart';
import 'pos_screen.dart';
import 'report_screen.dart';
import 'stock_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final _kasirNavigator = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<TabNav>();
    final cartCount = context.select<Cart, int>((c) => c.count);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Tombol back Android: tutup Checkout dulu, lalu kembali ke Home, baru keluar app.
        final kasir = _kasirNavigator.currentState;
        if (nav.current == AppTab.kasir && kasir != null && kasir.canPop()) {
          kasir.pop();
        } else if (nav.current != AppTab.home) {
          nav.go(AppTab.home);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: nav.current.index,
          children: [
            const HomeScreen(),
            Navigator(
              key: _kasirNavigator,
              onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const PosScreen()),
            ),
            const StockScreen(),
            const ExpenseScreen(),
            const ReportScreen(),
            const ChatScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: nav.current.index,
          onDestinationSelected: (i) => nav.go(AppTab.values[i]),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Beranda'),
            NavigationDestination(
              icon: Badge(isLabelVisible: cartCount > 0, label: Text('$cartCount'), child: const Icon(Icons.point_of_sale_outlined)),
              selectedIcon: Badge(isLabelVisible: cartCount > 0, label: Text('$cartCount'), child: const Icon(Icons.point_of_sale)),
              label: 'Kasir',
            ),
            const NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Stok'),
            const NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Biaya'),
            const NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Laporan'),
            const NavigationDestination(icon: Icon(Icons.forum_outlined), selectedIcon: Icon(Icons.forum), label: 'Asisten'),
          ],
        ),
      ),
    );
  }
}
