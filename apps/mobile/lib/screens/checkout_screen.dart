// apps/mobile/lib/screens/checkout_screen.dart
// List item + tombol +/−, pilih metode cash/qris/debit, input uang bayar → kembalian otomatis.
// Submit → RPC create_transaction (insert transaksi + item + auto-deduct stok + stock_movements).
// QRIS → QrisScreen (Midtrans); transaksi dicatat server setelah lunas. Tetap ada opsi catat manual (QRIS statis).
import 'package:coffee_core/coffee_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/cart.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'qris_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

/// Saran nominal tunai: uang pas + pembulatan ke pecahan umum.
List<double> quickAmounts(double total) {
  final options = <double>{total};
  for (final step in [10000, 20000, 50000, 100000]) {
    final rounded = (total / step).ceil() * step.toDouble();
    if (rounded > total) options.add(rounded);
  }
  final sorted = options.toList()..sort();
  return sorted.take(4).toList();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  PaymentMethod _method = PaymentMethod.cash;
  final _paid = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _paid.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _paid.dispose();
    super.dispose();
  }

  /// QRIS dinamis: transaksi dicatat server setelah Midtrans menyatakan lunas.
  Future<void> _payWithQris(Cart cart) async {
    final navigator = Navigator.of(context);
    final tx = await navigator.push<SaleTransaction>(
      MaterialPageRoute(builder: (_) => QrisScreen(lines: List.of(cart.lines))),
    );
    if (tx == null || !mounted) return;
    cart.clear();
    await _showSuccess(tx);
    navigator.popUntil((route) => route.isFirst);
  }

  Future<void> _showSuccess(SaleTransaction tx) => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: AppColors.success, size: 48),
          title: const Text('Transaksi berhasil'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tx.invoiceNo, style: const TextStyle(fontFamily: 'monospace')),
              const SizedBox(height: 8),
              Text('Total: ${formatRupiah(tx.total)}'),
              if (tx.paymentMethod == PaymentMethod.cash) ...[
                Text('Bayar: ${formatRupiah(tx.paidAmount)}'),
                Text('Kembalian: ${formatRupiah(tx.change)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              ] else
                Text('Metode: ${tx.paymentMethod.label}'),
            ],
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Transaksi baru'))],
        ),
      );

  Future<void> _submit(Cart cart) async {
    final total = cart.total;
    final paid = _method == PaymentMethod.cash ? parseMoney(_paid.text) : total;
    if (_method == PaymentMethod.cash && (paid == null || paid < total)) {
      setState(() => _error = 'Uang bayar kurang dari total.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final repo = context.read<CoffeeRepository>();
    final navigator = Navigator.of(context);
    try {
      final tx = await repo.createTransaction(items: cart.lines, method: _method, paidAmount: paid);
      cart.clear();
      if (!mounted) return;
      await _showSuccess(tx);
      navigator.popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<Cart>();
    final total = cart.total;
    final paid = _method == PaymentMethod.cash ? parseMoney(_paid.text) : total;
    final change = paid == null ? null : paid - total;
    final canSubmit = !cart.isEmpty && (_method != PaymentMethod.cash || (paid != null && paid >= total));

    if (cart.isEmpty && !_submitting) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pembayaran')),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.shopping_cart_outlined, size: 48, color: AppColors.muted),
            const SizedBox(height: 8),
            const Text('Keranjang kosong', style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Kembali ke menu')),
          ]),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Pembayaran')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MessageBanner(message: _error),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pesanan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  for (final line in cart.lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(line.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                Text('${formatRupiah(line.price)} × ${line.qty} = ${formatRupiah(line.subtotal)}',
                                    style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                              ],
                            ),
                          ),
                          IconButton.outlined(
                            onPressed: () => cart.decrement(line.menuItemId),
                            icon: const Icon(Icons.remove, size: 18),
                            tooltip: 'Kurangi',
                          ),
                          SizedBox(
                            width: 32,
                            child: Text('${line.qty}',
                                textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          ),
                          IconButton.outlined(
                            onPressed: () => cart.increment(line.menuItemId),
                            icon: const Icon(Icons.add, size: 18),
                            tooltip: 'Tambah',
                          ),
                        ],
                      ),
                    ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      Text(formatRupiah(total),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Metode pembayaran', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  SegmentedButton<PaymentMethod>(
                    segments: const [
                      ButtonSegment(value: PaymentMethod.cash, label: Text('Tunai'), icon: Icon(Icons.payments_outlined)),
                      ButtonSegment(value: PaymentMethod.qris, label: Text('QRIS'), icon: Icon(Icons.qr_code_2)),
                      ButtonSegment(value: PaymentMethod.debit, label: Text('Debit'), icon: Icon(Icons.credit_card)),
                    ],
                    selected: {_method},
                    onSelectionChanged: (s) => setState(() => _method = s.first),
                  ),
                  if (_method == PaymentMethod.cash) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _paid,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(labelText: 'Uang diterima', prefixText: 'Rp ', hintText: total.round().toString()),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final amount in quickAmounts(total))
                          ActionChip(
                            label: Text(amount == total ? 'Uang pas' : formatRupiah(amount)),
                            onPressed: () => _paid.text = amount.round().toString(),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Kembalian', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        Text(
                          change == null
                              ? '—'
                              : change < 0
                                  ? 'Kurang ${formatRupiah(-change)}'
                                  : formatRupiah(change),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: (change ?? 0) < 0 ? AppColors.danger : AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ] else if (_method == PaymentMethod.qris) ...[
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'QR dibuat otomatis (Midtrans). Transaksi tersimpan sendiri setelah pelanggan membayar.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _submitting ? null : () => _submit(cart),
                        child: const Text('Sudah dibayar via QRIS statis? Catat manual'),
                      ),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'Pastikan pembayaran ${_method.label} sebesar ${formatRupiah(total)} sudah diterima sebelum menyimpan.',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_method == PaymentMethod.qris)
            FilledButton.icon(
              onPressed: canSubmit && !_submitting ? () => _payWithQris(cart) : null,
              icon: const Icon(Icons.qr_code_2),
              label: Text('Tampilkan QRIS · ${formatRupiah(total)}'),
            )
          else
            FilledButton(
              onPressed: canSubmit && !_submitting ? () => _submit(cart) : null,
              child: _submitting
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Text('Simpan transaksi · ${formatRupiah(total)}'),
            ),
        ],
      ),
    );
  }
}
