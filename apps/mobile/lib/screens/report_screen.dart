// apps/mobile/lib/screens/report_screen.dart
// Omset hari ini / 7 hari / bulan ini + omset per hari + menu terlaris.
import 'package:coffee_core/coffee_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_controller.dart';
import '../state/tab_nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/tab_refresh.dart';

enum ReportRange { today, week, month }

class _Report {
  const _Report(this.start, this.end, this.daily, this.topMenus);
  final String start;
  final String end;
  final List<RevenueByDay> daily;
  final List<MenuPerformance> topMenus;

  double get revenue => daily.fold(0, (s, d) => s + d.revenue);
  int get transactions => daily.fold(0, (s, d) => s + d.txCount);
  double get average => transactions == 0 ? 0 : revenue / transactions;
}

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> with TabRefresh<ReportScreen> {
  ReportRange _range = ReportRange.today;
  _Report? _report;
  bool _loading = true;
  String? _error;

  @override
  AppTab get tab => AppTab.laporan;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  Future<void> refresh() async {
    final repo = context.read<CoffeeRepository>();
    final end = jakartaDate();
    final start = switch (_range) {
      ReportRange.today => end,
      ReportRange.week => addDays(end, -6),
      ReportRange.month => startOfMonth(end),
    };
    setState(() => _loading = true);
    try {
      final results = await Future.wait([repo.revenueByDay(start, end), repo.menuPerformance(start, end)]);
      if (!mounted) return;
      final menus = (results[1] as List<MenuPerformance>).where((m) => m.qtySold > 0).take(5).toList();
      setState(() {
        _report = _Report(start, end, results[0] as List<RevenueByDay>, menus);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthController>().isAdmin;
    final report = _report;
    final maxDaily = report == null || report.daily.isEmpty
        ? 1.0
        : report.daily.map((d) => d.revenue).reduce((a, b) => a > b ? a : b).clamp(1, double.infinity).toDouble();

    return Scaffold(
      appBar: AppBar(title: const Text('Laporan')),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<ReportRange>(
              segments: const [
                ButtonSegment(value: ReportRange.today, label: Text('Hari ini')),
                ButtonSegment(value: ReportRange.week, label: Text('7 hari')),
                ButtonSegment(value: ReportRange.month, label: Text('Bulan ini')),
              ],
              selected: {_range},
              onSelectionChanged: (s) {
                setState(() => _range = s.first);
                refresh();
              },
            ),
            const SizedBox(height: 8),
            if (!isAdmin)
              const Text('Menampilkan transaksi yang Anda input sebagai kasir.',
                  style: TextStyle(fontSize: 12, color: AppColors.muted)),
            const SizedBox(height: 8),
            MessageBanner(message: _error),
            if (_loading && report == null)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else if (report != null) ...[
              Text(
                report.start == report.end ? longDate(report.start) : '${shortDate(report.start)} – ${shortDate(report.end)}',
                style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              KpiTile(label: 'Omset', value: formatRupiah(report.revenue), tone: AppColors.successSoft),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: KpiTile(label: 'Transaksi', value: formatNumber(report.transactions))),
                const SizedBox(width: 8),
                Expanded(child: KpiTile(label: 'Rata-rata', value: formatRupiah(report.average), hint: 'per transaksi')),
              ]),
              if (report.daily.length > 1) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Omset per hari', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 12),
                        for (final d in report.daily)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(children: [
                              SizedBox(width: 52, child: Text(shortDate(d.day), style: const TextStyle(fontSize: 12, color: AppColors.muted))),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: (d.revenue / maxDaily).clamp(0.01, 1.0),
                                    minHeight: 10,
                                    color: AppColors.info,
                                    backgroundColor: AppColors.primarySoft,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 100,
                                child: Text(formatRupiah(d.revenue),
                                    textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              ),
                            ]),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Menu terlaris', style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      if (report.topMenus.isEmpty)
                        const Text('Belum ada penjualan.', style: TextStyle(color: AppColors.muted))
                      else
                        for (final (i, m) in report.topMenus.indexed)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(children: [
                              Expanded(child: Text('${i + 1}. ${m.name}', style: const TextStyle(fontWeight: FontWeight.w600))),
                              Text('${formatNumber(m.qtySold)}×',
                                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
                            ]),
                          ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
