// apps/admin/lib/pages/dashboard_page.dart
// 4 KPI (omset hari ini, 7 hari, bulan ini, pengeluaran bulan ini), tren 30 hari,
// peringatan stok menipis, top 5 terlaris & 5 jarang laku (30 hari).
import 'package:coffee_core/coffee_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

class _DashboardData {
  _DashboardData({
    required this.today,
    required this.daily,
    required this.monthStart,
    required this.expensesMonth,
    required this.lowStock,
    required this.menus,
  });

  final String today;
  final String monthStart;
  final List<RevenueByDay> daily;
  final double expensesMonth;
  final List<Ingredient> lowStock;
  final List<MenuPerformance> menus;

  RevenueByDay? get todayRow => daily.where((d) => d.day == today).firstOrNull;
  Iterable<RevenueByDay> get last7 => daily.where((d) => d.day.compareTo(addDays(today, -6)) >= 0);
  Iterable<RevenueByDay> get month => daily.where((d) => d.day.compareTo(monthStart) >= 0);
  List<RevenueByDay> get trend => daily.where((d) => d.day.compareTo(addDays(today, -29)) >= 0).toList();

  double get revenueMonth => month.fold(0, (s, d) => s + d.revenue);

  List<MenuPerformance> get top =>
      (menus.where((m) => m.qtySold > 0).toList()..sort((a, b) => b.qtySold.compareTo(a.qtySold))).take(5).toList();

  List<MenuPerformance> get slow => (menus.where((m) => m.isActive).toList()
        ..sort((a, b) {
          final byQty = a.qtySold.compareTo(b.qtySold);
          return byQty != 0 ? byQty : a.revenue.compareTo(b.revenue);
        }))
      .take(5)
      .toList();
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  _DashboardData? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<CoffeeRepository>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final today = jakartaDate();
      final monthStart = startOfMonth(today);
      final trendStart = addDays(today, -29);
      final rangeStart = monthStart.compareTo(trendStart) < 0 ? monthStart : trendStart;
      final results = await Future.wait([
        repo.revenueByDay(rangeStart, today),
        repo.expensesInRange(monthStart, today),
        repo.ingredients(),
        repo.menuPerformance(trendStart, today),
      ]);
      if (!mounted) return;
      setState(() {
        _data = _DashboardData(
          today: today,
          monthStart: monthStart,
          daily: results[0] as List<RevenueByDay>,
          expensesMonth: (results[1] as List<Expense>).fold(0, (s, e) => s + e.amount),
          lowStock: (results[2] as List<Ingredient>).where((i) => i.isLow).toList(),
          menus: results[3] as List<MenuPerformance>,
        );
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return PageScaffold(
      title: 'Dashboard',
      subtitle: d == null ? 'Memuat ringkasan…' : 'Ringkasan per ${longDate(d.today)} (WIB)',
      actions: [
        OutlinedButton.icon(
          onPressed: _loading ? null : _load,
          icon: _loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh, size: 18),
          label: const Text('Muat ulang'),
        ),
      ],
      children: [
        NoticeBanner(message: _error),
        if (d == null && _loading) const LoadingBox(),
        if (d != null) ...[
          KpiGrid(children: [
            KpiCard(
              label: 'Omset hari ini',
              value: formatRupiah(d.todayRow?.revenue ?? 0),
              hint: '${d.todayRow?.txCount ?? 0} transaksi',
              icon: Icons.today,
            ),
            KpiCard(
              label: 'Omset 7 hari',
              value: formatRupiah(d.last7.fold<double>(0, (s, r) => s + r.revenue)),
              hint: '${d.last7.fold<int>(0, (s, r) => s + r.txCount)} transaksi',
              icon: Icons.date_range,
            ),
            KpiCard(
              label: 'Omset bulan ini',
              value: formatRupiah(d.revenueMonth),
              hint: 'Sejak tanggal 1',
              icon: Icons.account_balance_wallet_outlined,
              tone: AppColors.success,
              toneBg: AppColors.successSoft,
            ),
            KpiCard(
              label: 'Pengeluaran bulan ini',
              value: formatRupiah(d.expensesMonth),
              hint: 'Omset − pengeluaran: ${formatRupiah(d.revenueMonth - d.expensesMonth)}',
              icon: Icons.trending_down,
              tone: AppColors.danger,
              toneBg: AppColors.dangerSoft,
            ),
          ]),
          const SizedBox(height: 16),
          ResponsiveRow(flex: const [2, 1], children: [
            SectionCard(
              title: 'Tren omset 30 hari',
              subtitle: 'Omset harian (transaksi berstatus paid)',
              child: RevenueTrendChart(data: d.trend),
            ),
            SectionCard(
              title: 'Stok menipis',
              trailing: d.lowStock.isEmpty
                  ? const Pill('Aman', fg: AppColors.success, bg: AppColors.successSoft)
                  : Pill('${d.lowStock.length} bahan', fg: AppColors.warning, bg: AppColors.warningSoft),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (d.lowStock.isEmpty)
                    const Text('Semua bahan di atas stok minimum.', style: TextStyle(color: AppColors.muted)),
                  for (final i in d.lowStock)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(8)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.warning_amber, size: 18, color: AppColors.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(i.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(
                              'Sisa ${formatNumber(i.currentStock)} ${i.unit} · minimum ${formatNumber(i.minStock)} ${i.unit}'
                              '${i.currentStock <= 0 ? ' (HABIS)' : ''}',
                              style: const TextStyle(fontSize: 12, color: AppColors.muted),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                  TextButton(onPressed: () => context.go('/ingredients'), child: const Text('Kelola stok →')),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 16),
          ResponsiveRow(children: [
            _MenuList(title: 'Top 5 menu terlaris', rows: d.top, empty: 'Belum ada penjualan 30 hari terakhir.', color: AppColors.revenue),
            _MenuList(title: '5 menu jarang laku', rows: d.slow, empty: 'Belum ada menu aktif.', color: AppColors.muted),
          ]),
        ],
      ],
    );
  }
}

class _MenuList extends StatelessWidget {
  const _MenuList({required this.title, required this.rows, required this.empty, required this.color});

  final String title;
  final List<MenuPerformance> rows;
  final String empty;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final max = rows.fold<int>(1, (m, r) => r.qtySold > m ? r.qtySold : m);
    return SectionCard(
      title: title,
      subtitle: '30 hari terakhir, berdasarkan jumlah terjual',
      child: rows.isEmpty
          ? Text(empty, style: const TextStyle(color: AppColors.muted))
          : Column(children: [
              for (final (i, r) in rows.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('${i + 1}. ${r.name}', style: const TextStyle(fontWeight: FontWeight.w600))),
                      Text('${formatNumber(r.qtySold)} terjual · ${formatRupiah(r.revenue)}',
                          style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                    ]),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (r.qtySold / max).clamp(0.02, 1.0),
                        minHeight: 6,
                        color: color,
                        backgroundColor: AppColors.grid,
                      ),
                    ),
                  ]),
                ),
            ]),
    );
  }
}
