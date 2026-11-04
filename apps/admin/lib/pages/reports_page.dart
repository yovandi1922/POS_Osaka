// apps/admin/lib/pages/reports_page.dart
// KPI pendapatan/pengeluaran/laba + chart harian + breakdown per kategori menu & kategori pengeluaran.
import 'package:coffee_core/coffee_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

enum _Range { d7, d30, d90, month }

extension on _Range {
  String get label => switch (this) { _Range.d7 => '7 hari', _Range.d30 => '30 hari', _Range.d90 => '90 hari', _Range.month => 'Bulan ini' };
}

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  _Range _range = _Range.d30;
  String _start = '';
  String _end = '';
  List<RevenueByDay> _daily = [];
  List<Expense> _expenses = [];
  List<MenuPerformance> _menus = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<CoffeeRepository>();
    final end = jakartaDate();
    final start = switch (_range) {
      _Range.d7 => addDays(end, -6),
      _Range.d30 => addDays(end, -29),
      _Range.d90 => addDays(end, -89),
      _Range.month => startOfMonth(end),
    };
    setState(() => _loading = true);
    try {
      final r = await Future.wait([repo.revenueByDay(start, end), repo.expensesInRange(start, end), repo.menuPerformance(start, end)]);
      if (!mounted) return;
      setState(() {
        _start = start;
        _end = end;
        _daily = r[0] as List<RevenueByDay>;
        _expenses = r[1] as List<Expense>;
        _menus = r[2] as List<MenuPerformance>;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<MapEntry<String, double>> _sorted(Map<String, double> m) =>
      (m.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value)));

  @override
  Widget build(BuildContext context) {
    final revenue = _daily.fold<double>(0, (s, d) => s + d.revenue);
    final txCount = _daily.fold<int>(0, (s, d) => s + d.txCount);
    final totalExpense = _expenses.fold<double>(0, (s, e) => s + e.amount);
    final profit = revenue - totalExpense;
    final margin = revenue > 0 ? (profit / revenue * 100).round() : 0;

    final expenseByDay = <String, double>{};
    final expenseByCategory = <String, double>{};
    for (final e in _expenses) {
      expenseByDay[e.expenseDate] = (expenseByDay[e.expenseDate] ?? 0) + e.amount;
      expenseByCategory[e.category] = (expenseByCategory[e.category] ?? 0) + e.amount;
    }
    final revenueByMenuCategory = <String, double>{};
    for (final m in _menus) {
      revenueByMenuCategory[m.category] = (revenueByMenuCategory[m.category] ?? 0) + m.revenue;
    }

    return PageScaffold(
      title: 'Laporan',
      subtitle: _start.isEmpty ? 'Memuat…' : '${longDate(_start)} – ${longDate(_end)} · $txCount transaksi',
      actions: [
        SegmentedButton<_Range>(
          segments: [for (final r in _Range.values) ButtonSegment(value: r, label: Text(r.label))],
          selected: {_range},
          onSelectionChanged: (s) {
            setState(() => _range = s.first);
            _load();
          },
        ),
      ],
      children: [
        NoticeBanner(message: _error),
        if (_loading && _daily.isEmpty)
          const LoadingBox()
        else ...[
          KpiGrid(maxColumns: 3, children: [
            KpiCard(
              label: 'Pendapatan',
              value: formatRupiah(revenue),
              hint: 'Rata-rata ${formatRupiah(txCount == 0 ? 0 : revenue / txCount)}/transaksi',
              icon: Icons.account_balance_wallet_outlined,
              tone: AppColors.success,
              toneBg: AppColors.successSoft,
            ),
            KpiCard(
              label: 'Pengeluaran',
              value: formatRupiah(totalExpense),
              hint: '${_expenses.length} catatan',
              icon: Icons.trending_down,
              tone: AppColors.danger,
              toneBg: AppColors.dangerSoft,
            ),
            KpiCard(
              label: 'Laba (pendapatan − pengeluaran)',
              value: formatRupiah(profit),
              hint: 'Margin $margin%',
              icon: Icons.savings_outlined,
              tone: profit >= 0 ? AppColors.success : AppColors.danger,
              toneBg: profit >= 0 ? AppColors.successSoft : AppColors.dangerSoft,
            ),
          ]),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Pendapatan vs pengeluaran harian',
            subtitle: 'Pengeluaran dicatat per tanggal pengeluaran',
            child: RevenueExpenseChart(
              data: [for (final d in _daily) RevenueExpensePoint(d.day, d.revenue, expenseByDay[d.day] ?? 0)],
            ),
          ),
          const SizedBox(height: 16),
          ResponsiveRow(children: [
            SectionCard(
              title: 'Pendapatan per kategori menu',
              child: revenueByMenuCategory.values.every((v) => v <= 0)
                  ? const Text('Belum ada penjualan pada periode ini.', style: TextStyle(color: AppColors.muted))
                  : CategoryBars(rows: _sorted(revenueByMenuCategory), color: AppColors.revenue, total: revenue),
            ),
            SectionCard(
              title: 'Pengeluaran per kategori',
              child: expenseByCategory.isEmpty
                  ? const Text('Belum ada pengeluaran pada periode ini.', style: TextStyle(color: AppColors.muted))
                  : CategoryBars(rows: _sorted(expenseByCategory), color: AppColors.expense, total: totalExpense),
            ),
          ]),
          const SizedBox(height: 16),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Penjualan per menu', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              ScrollTable(
                table: DataTable(
                  columns: const [
                    DataColumn(label: Text('MENU')),
                    DataColumn(label: Text('KATEGORI')),
                    DataColumn(label: Text('TERJUAL'), numeric: true),
                    DataColumn(label: Text('PENDAPATAN'), numeric: true),
                  ],
                  rows: [
                    for (final m in _menus)
                      DataRow(cells: [
                        DataCell(Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Text(m.category)),
                        DataCell(Text(formatNumber(m.qtySold))),
                        DataCell(Text(formatRupiah(m.revenue))),
                      ]),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ],
    );
  }
}
