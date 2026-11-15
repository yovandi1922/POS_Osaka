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

const _txLimit = 200;

class _Report {
  const _Report(this.start, this.end, this.daily, this.topMenus, this.txList);
  final String start;
  final String end;
  final List<RevenueByDay> daily;
  final List<MenuPerformance> topMenus;
  final List<SaleTransaction> txList;

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
      final results = await Future.wait([
        repo.revenueByDay(start, end),
        repo.menuPerformance(start, end),
        repo.recentTransactions(from: start, to: end, limit: _txLimit),
      ]);
      if (!mounted) return;
      final menus = (results[1] as List<MenuPerformance>).where((m) => m.qtySold > 0).take(5).toList();
      setState(() {
        _report = _Report(start, end, results[0] as List<RevenueByDay>, menus, results[2] as List<SaleTransaction>);
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
              const SizedBox(height: 12),
              _TransactionList(report: report, showCashier: isAdmin),
            ],
          ],
        ),
      ),
    );
  }
}

/// Daftar transaksi periode terpilih; ketuk satu baris → detail.
class _TransactionList extends StatelessWidget {
  const _TransactionList({required this.report, required this.showCashier});

  final _Report report;
  final bool showCashier;

  @override
  Widget build(BuildContext context) {
    final txs = report.txList;
    final singleDay = report.start == report.end;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(children: [
              const Expanded(child: Text('Daftar transaksi', style: TextStyle(fontWeight: FontWeight.w800))),
              Text('${formatNumber(txs.length)} transaksi', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ]),
          ),
          if (txs.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text('Belum ada transaksi.', style: TextStyle(color: AppColors.muted)),
            )
          else ...[
            for (final (i, tx) in txs.indexed) ...[
              if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
              InkWell(
                onTap: () => showTransactionDetail(context, tx, showCashier: showCashier),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(singleDay ? formatTime(tx.createdAt) : formatDateTime(tx.createdAt),
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(width: 8),
                          _MethodChip(tx.paymentMethod),
                          if (!tx.isPaid) ...[const SizedBox(width: 6), _StatusChip(tx.status)],
                        ]),
                        const SizedBox(height: 2),
                        Text(
                          '${tx.invoiceNo} · ${formatNumber(tx.itemCount)} item',
                          style: const TextStyle(fontSize: 12, color: AppColors.muted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ]),
                    ),
                    Text(formatRupiah(tx.total),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: tx.isPaid ? AppColors.text : AppColors.muted,
                          decoration: tx.isPaid ? null : TextDecoration.lineThrough,
                        )),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, color: AppColors.muted),
                  ]),
                ),
              ),
            ],
            if (txs.length >= _txLimit)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Menampilkan $_txLimit transaksi terbaru.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
              )
            else
              const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _MethodChip extends StatelessWidget {
  const _MethodChip(this.method);

  final PaymentMethod method;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(6)),
        child: Text(method.label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary)),
      );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);

  final String status;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: AppColors.dangerSoft, borderRadius: BorderRadius.circular(6)),
        child: Text(status == 'void' ? 'Dibatalkan' : status,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.danger)),
      );
}

/// Bottom sheet rincian satu transaksi (struk).
Future<void> showTransactionDetail(BuildContext context, SaleTransaction tx, {bool showCashier = false}) {
  Widget row(String label, String value, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted))),
          Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color, fontSize: bold ? 17 : null)),
        ]),
      );

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Row(children: [
            Expanded(
              child: Text(tx.invoiceNo,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            if (!tx.isPaid) _StatusChip(tx.status),
          ]),
          const SizedBox(height: 4),
          Text(formatDateTime(tx.createdAt), style: const TextStyle(color: AppColors.muted)),
          if (showCashier && tx.cashierName != null)
            Text('Kasir: ${tx.cashierName}', style: const TextStyle(color: AppColors.muted)),
          const Divider(height: 24),
          if (tx.items.isEmpty)
            const Text('Tidak ada rincian item.', style: TextStyle(color: AppColors.muted))
          else
            for (final item in tx.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item.menuName ?? 'Menu dihapus', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('${formatRupiah(item.price)} × ${item.qty}',
                          style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                      if (item.notes != null && item.notes!.isNotEmpty)
                        Text('Catatan: ${item.notes}', style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                    ]),
                  ),
                  Text(formatRupiah(item.subtotal), style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
          const Divider(height: 24),
          row('Subtotal', formatRupiah(tx.subtotal)),
          if (tx.discount > 0) row('Diskon', '− ${formatRupiah(tx.discount)}', color: AppColors.danger),
          row('Total', formatRupiah(tx.total), bold: true, color: AppColors.primary),
          const SizedBox(height: 8),
          row('Metode', tx.paymentMethod.label),
          if (tx.paymentMethod == PaymentMethod.cash) ...[
            row('Dibayar', formatRupiah(tx.paidAmount)),
            row('Kembalian', formatRupiah(tx.change)),
          ],
        ],
      ),
    ),
  );
}
