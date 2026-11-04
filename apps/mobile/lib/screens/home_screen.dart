// apps/mobile/lib/screens/home_screen.dart
// KPI hari ini (omset, jumlah transaksi, stok menipis) + tombol aksi cepat.
import 'package:coffee_core/coffee_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_controller.dart';
import '../state/tab_nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/tab_refresh.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeKpi {
  const _HomeKpi(this.revenue, this.tx, this.lowStock);
  final double revenue;
  final int tx;
  final int lowStock;
}

class _HomeScreenState extends State<HomeScreen> with TabRefresh<HomeScreen> {
  _HomeKpi? _kpi;
  String? _error;

  @override
  AppTab get tab => AppTab.home;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  Future<void> refresh() async {
    final repo = context.read<CoffeeRepository>();
    final today = jakartaDate();
    try {
      final results = await Future.wait([repo.revenueByDay(today, today), repo.ingredients()]);
      final daily = results[0] as List<RevenueByDay>;
      final ingredients = results[1] as List<Ingredient>;
      if (!mounted) return;
      setState(() {
        _error = null;
        _kpi = _HomeKpi(
          daily.isEmpty ? 0 : daily.first.revenue,
          daily.isEmpty ? 0 : daily.first.txCount,
          ingredients.where((i) => i.isLow).length,
        );
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _confirmLogout() async {
    final auth = context.read<AuthController>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keluar'),
        content: const Text('Yakin ingin keluar dari akun ini?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger, minimumSize: const Size(64, 40)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (ok == true) await auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final profile = auth.profile;
    final nav = context.read<TabNav>();
    final kpi = _kpi;
    final scope = auth.isAdmin ? 'seluruh toko' : 'transaksi Anda';

    final actions = <(String, IconData, AppTab)>[
      ('Transaksi baru', Icons.point_of_sale, AppTab.kasir),
      ('Stok masuk', Icons.inventory_2, AppTab.stok),
      ('Catat biaya', Icons.account_balance_wallet, AppTab.pengeluaran),
      ('Tanya Kopi', Icons.forum, AppTab.asisten),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Beranda'),
        actions: [
          IconButton(onPressed: _confirmLogout, tooltip: 'Keluar', icon: const Icon(Icons.logout)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Halo, ${profile?.displayName ?? 'Barista'} 👋',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            Text('${profile?.role.label ?? 'Kasir'} · ${longDate(jakartaDate())}',
                style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            MessageBanner(message: _error),
            Text('HARI INI ($scope)',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted)),
            const SizedBox(height: 8),
            KpiTile(label: 'Omset', value: kpi == null ? '…' : formatRupiah(kpi.revenue), tone: AppColors.successSoft),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: KpiTile(label: 'Transaksi', value: kpi == null ? '…' : '${kpi.tx}')),
                const SizedBox(width: 8),
                Expanded(
                  child: KpiTile(
                    label: 'Stok menipis',
                    value: kpi == null ? '…' : '${kpi.lowStock}',
                    hint: (kpi?.lowStock ?? 0) > 0 ? 'Cek tab Stok' : 'Semua aman',
                    tone: (kpi?.lowStock ?? 0) > 0 ? AppColors.warningSoft : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('AKSI CEPAT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted)),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: [
                for (final (label, icon, target) in actions)
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => nav.go(target),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                  color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
                              child: Icon(icon, color: AppColors.primary),
                            ),
                            Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
