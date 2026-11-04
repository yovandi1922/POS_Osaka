// apps/admin/lib/pages/transactions_page.dart
// 100 transaksi terakhir dengan join profiles (kasir) + transaction_items.
import 'package:coffee_core/coffee_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme.dart';
import '../widgets/common.dart';

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  List<SaleTransaction> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await context.read<CoffeeRepository>().recentTransactions(limit: 100);
      if (mounted) {
        setState(() {
          _rows = rows;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showItems(SaleTransaction t) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.invoiceNo),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${formatDateTime(t.createdAt)} · ${t.cashierName ?? '—'}', style: const TextStyle(color: AppColors.muted)),
              const Divider(),
              for (final i in t.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(child: Text('${i.qty}× ${i.menuName ?? 'Menu dihapus'}${i.notes != null ? ' (${i.notes})' : ''}')),
                    Text(formatRupiah(i.subtotal)),
                  ]),
                ),
              const Divider(),
              _kv('Subtotal', formatRupiah(t.subtotal)),
              if (t.discount > 0) _kv('Diskon', '-${formatRupiah(t.discount)}'),
              _kv('Total', formatRupiah(t.total), bold: true),
              _kv('Metode', t.paymentMethod.label),
              if (t.paymentMethod == PaymentMethod.cash) ...[
                _kv('Dibayar', formatRupiah(t.paidAmount)),
                _kv('Kembalian', formatRupiah(t.change)),
              ],
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup'))],
      ),
    );
  }

  Widget _kv(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(k)),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w400)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final paid = _rows.where((r) => r.isPaid);
    final total = paid.fold<double>(0, (s, r) => s + r.total);
    return PageScaffold(
      title: 'Transaksi',
      subtitle: '100 transaksi terakhir · total ${formatRupiah(total)} dari ${paid.length} transaksi lunas',
      actions: [OutlinedButton.icon(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh, size: 18), label: const Text('Muat ulang'))],
      children: [
        NoticeBanner(message: _error),
        Card(
          clipBehavior: Clip.antiAlias,
          child: _loading && _rows.isEmpty
              ? const LoadingBox()
              : _rows.isEmpty
                  ? const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Belum ada transaksi.')))
                  : ScrollTable(
                      table: DataTable(
                        showCheckboxColumn: false,
                        columns: const [
                          DataColumn(label: Text('INVOICE')),
                          DataColumn(label: Text('WAKTU (WIB)')),
                          DataColumn(label: Text('KASIR')),
                          DataColumn(label: Text('ITEM')),
                          DataColumn(label: Text('METODE')),
                          DataColumn(label: Text('DISKON'), numeric: true),
                          DataColumn(label: Text('TOTAL'), numeric: true),
                          DataColumn(label: Text('STATUS')),
                        ],
                        rows: [
                          for (final t in _rows)
                            DataRow(
                              onSelectChanged: (_) => _showItems(t),
                              cells: [
                                DataCell(Text(t.invoiceNo, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
                                DataCell(Text(formatDateTime(t.createdAt))),
                                DataCell(Text(t.cashierName ?? '—')),
                                DataCell(Tooltip(
                                  message: t.items.map((i) => '${i.qty}× ${i.menuName ?? '?'}').join('\n'),
                                  child: Text('${t.itemCount} item ▸'),
                                )),
                                DataCell(Pill(t.paymentMethod.label, fg: AppColors.text, bg: const Color(0xFFF5F5F4))),
                                DataCell(Text(t.discount > 0 ? formatRupiah(t.discount) : '—')),
                                DataCell(Text(formatRupiah(t.total), style: const TextStyle(fontWeight: FontWeight.w700))),
                                DataCell(t.isPaid
                                    ? const Pill('Lunas', fg: AppColors.success, bg: AppColors.successSoft)
                                    : const Pill('Void', fg: AppColors.danger, bg: AppColors.dangerSoft)),
                              ],
                            ),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }
}
