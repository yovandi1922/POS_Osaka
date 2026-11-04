// apps/admin/lib/widgets/shell.dart
// Layout dashboard: sidebar (Dashboard, AI, Transaksi, Menu, Stok, Pengeluaran, Laporan, Prediksi, Pengguna, Logout).
// Layar lebar → sidebar permanen; layar sempit → drawer.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/admin_session.dart';
import '../theme.dart';

class _NavItem {
  const _NavItem(this.path, this.label, this.icon);
  final String path;
  final String label;
  final IconData icon;
}

const _nav = [
  _NavItem('/dashboard', 'Dashboard', Icons.dashboard_outlined),
  _NavItem('/chat', 'Asisten AI', Icons.smart_toy_outlined),
  _NavItem('/transactions', 'Transaksi', Icons.receipt_long_outlined),
  _NavItem('/menu', 'Menu', Icons.local_cafe_outlined),
  _NavItem('/ingredients', 'Stok Bahan', Icons.inventory_2_outlined),
  _NavItem('/expenses', 'Pengeluaran', Icons.account_balance_wallet_outlined),
  _NavItem('/reports', 'Laporan', Icons.bar_chart_outlined),
  _NavItem('/predictions', 'Prediksi', Icons.trending_up),
  _NavItem('/users', 'Pengguna', Icons.group_outlined),
];

class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final sidebar = _Sidebar(location: location, closeOnTap: !wide);
    if (wide) {
      return Scaffold(body: Row(children: [sidebar, Expanded(child: child)]));
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.coffee950,
        foregroundColor: Colors.white,
        title: const Row(children: [Icon(Icons.local_cafe), SizedBox(width: 8), Text('Coffee POS')]),
      ),
      drawer: Drawer(backgroundColor: AppColors.coffee950, child: sidebar),
      body: child,
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.location, required this.closeOnTap});

  final String location;
  final bool closeOnTap;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AdminSession>();
    final profile = session.profile;
    return Container(
      width: 240,
      color: AppColors.coffee950,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: AppColors.coffee600, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.local_cafe, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                const Flexible(
                  child: Text('Coffee POS',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final item in _nav)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Material(
                        color: location.startsWith(item.path) ? AppColors.coffee700 : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        child: ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          leading: Icon(item.icon,
                              size: 20, color: location.startsWith(item.path) ? Colors.white : AppColors.coffee200),
                          title: Text(item.label,
                              style: TextStyle(
                                color: location.startsWith(item.path) ? Colors.white : AppColors.coffee200,
                                fontWeight: FontWeight.w600,
                              )),
                          onTap: () {
                            if (closeOnTap) Navigator.of(context).pop();
                            context.go(item.path);
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(color: Colors.white24, height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile?.displayName ?? '-',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  Text(profile?.role.label ?? '', style: const TextStyle(color: AppColors.coffee200, fontSize: 12)),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: AppColors.coffee200, padding: EdgeInsets.zero),
                    onPressed: () => context.read<AdminSession>().signOut(),
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Logout'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
