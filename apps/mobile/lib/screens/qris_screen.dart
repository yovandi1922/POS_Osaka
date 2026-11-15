// apps/mobile/lib/screens/qris_screen.dart
// QRIS dinamis Midtrans: minta QR ke API → tampilkan → polling status tiap 3 detik.
// Saat lunas, server sudah mencatat transaksi (stok terpotong) → layar ditutup dengan SaleTransaction.
// Hasil pop: SaleTransaction bila lunas, null bila batal/kedaluwarsa.
import 'dart:async';

import 'package:coffee_core/coffee_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme.dart';
import '../widgets/common.dart';

const _pollEvery = Duration(seconds: 3);
const _simulatorUrl = 'https://simulator.sandbox.midtrans.com/v2/qris/index';

class QrisScreen extends StatefulWidget {
  const QrisScreen({super.key, required this.lines});

  /// Salinan isi keranjang saat QR dibuat.
  final List<CartLine> lines;

  @override
  State<QrisScreen> createState() => _QrisScreenState();
}

class _QrisScreenState extends State<QrisScreen> {
  QrisPayment? _payment;
  String? _error;
  bool _creating = true;
  bool _cancelling = false;
  bool _polling = false;
  Timer? _pollTimer;
  Timer? _clock;

  CoffeeApi get _api => context.read<CoffeeApi>();

  @override
  void initState() {
    super.initState();
    _create();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _payment?.isWaiting == true) setState(() {});
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    _pollTimer?.cancel();
    setState(() {
      _creating = true;
      _error = null;
      _payment = null;
    });
    try {
      final p = await _api.createQris(widget.lines);
      if (!mounted) return;
      setState(() => _payment = p);
      _pollTimer = Timer.periodic(_pollEvery, (_) => _poll());
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _poll() async {
    final current = _payment;
    if (current == null || !current.isWaiting || _polling || _cancelling) return;
    _polling = true;
    try {
      _apply(await _api.qrisStatus(current.orderId));
    } catch (_) {
      // Gangguan jaringan sesaat: coba lagi di putaran berikutnya.
    } finally {
      _polling = false;
    }
  }

  void _apply(QrisPayment p) {
    if (!mounted) return;
    setState(() => _payment = p);
    if (p.isWaiting) return;
    _pollTimer?.cancel();
    if (p.status == QrisStatus.paid && p.transaction != null) {
      HapticFeedback.mediumImpact();
      Navigator.pop(context, p.transaction);
    }
  }

  Future<void> _cancel() async {
    final p = _payment;
    if (p == null || !p.isWaiting) {
      Navigator.pop(context);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Batalkan QRIS?'),
        content: const Text('QR ini tidak bisa dipakai lagi. Pastikan pelanggan belum membayar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Tunggu')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Batalkan'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      final result = await _api.cancelQris(p.orderId);
      if (!mounted) return;
      if (result.status == QrisStatus.paid) {
        _apply(result); // ternyata sudah dibayar → tetap sukses
      } else {
        _pollTimer?.cancel();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  String _remaining(DateTime? expiresAt) {
    if (expiresAt == null) return '';
    final left = expiresAt.difference(DateTime.now());
    if (left.isNegative) return '00:00';
    final m = left.inMinutes.toString().padLeft(2, '0');
    final s = (left.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final p = _payment;
    return PopScope(
      canPop: p == null || !p.isWaiting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Bayar dengan QRIS')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_creating)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 80),
                child: Column(children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Membuat QRIS…', style: TextStyle(color: AppColors.muted)),
                ]),
              )
            else if (p == null)
              _ErrorState(message: _error ?? 'Gagal membuat QRIS.', onRetry: _create)
            else
              ..._paymentView(p),
          ],
        ),
      ),
    );
  }

  List<Widget> _paymentView(QrisPayment p) {
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Text(formatRupiah(p.grossAmount),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.primary)),
            const SizedBox(height: 4),
            Text(p.orderId, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppColors.muted)),
            const SizedBox(height: 16),
            if (p.isWaiting && p.qrString != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: QrImageView(data: p.qrString!, size: 260, backgroundColor: Colors.white),
              )
            else
              _StatusIcon(status: p.status),
            const SizedBox(height: 16),
            _statusLine(p),
          ]),
        ),
      ),
      if (p.error != null) ...[
        const SizedBox(height: 12),
        MessageBanner(message: p.error),
      ],
      const SizedBox(height: 12),
      if (p.isWaiting)
        OutlinedButton.icon(
          onPressed: _cancelling ? null : _cancel,
          icon: _cancelling
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.close),
          label: const Text('Batalkan QRIS'),
        )
      else ...[
        if (p.status == QrisStatus.expired || p.status == QrisStatus.cancelled)
          FilledButton.icon(onPressed: _create, icon: const Icon(Icons.refresh), label: const Text('Buat QR baru')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Kembali ke pembayaran')),
      ],
      if (!p.isProduction && p.isWaiting) ...[
        const SizedBox(height: 16),
        _SandboxHint(qrUrl: p.qrUrl),
      ],
    ];
  }

  Widget _statusLine(QrisPayment p) {
    final (text, color) = switch (p.status) {
      QrisStatus.pending => ('Menunggu pembayaran · ${_remaining(p.expiresAt)}', AppColors.muted),
      QrisStatus.processing => ('Pembayaran diterima, mencatat transaksi…', AppColors.success),
      QrisStatus.paid => ('Lunas', AppColors.success),
      QrisStatus.expired => ('QR kedaluwarsa', AppColors.warning),
      QrisStatus.cancelled => ('QR dibatalkan', AppColors.muted),
      QrisStatus.failed => ('Perlu dicek manual', AppColors.danger),
    };
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      if (p.isWaiting) ...[
        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 8),
      ],
      Flexible(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700))),
    ]);
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final QrisStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      QrisStatus.paid || QrisStatus.processing => (Icons.check_circle, AppColors.success),
      QrisStatus.expired => (Icons.timer_off_outlined, AppColors.warning),
      QrisStatus.failed => (Icons.error_outline, AppColors.danger),
      _ => (Icons.block, AppColors.muted),
    };
    return Padding(padding: const EdgeInsets.all(40), child: Icon(icon, size: 96, color: color));
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 24),
        const Icon(Icons.qr_code_2, size: 64, color: AppColors.muted),
        const SizedBox(height: 12),
        MessageBanner(message: message),
        FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Coba lagi')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Kembali')),
      ]);
}

/// Petunjuk uji coba sandbox: QR sandbox tidak bisa di-scan e-wallet asli.
class _SandboxHint extends StatelessWidget {
  const _SandboxHint({required this.qrUrl});

  final String? qrUrl;

  void _copy(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    showSnack(context, '$label disalin.');
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.science_outlined, size: 18, color: AppColors.warning),
            SizedBox(width: 8),
            Text('Mode sandbox (uji coba)', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.warning)),
          ]),
          const SizedBox(height: 6),
          const Text(
            'QR ini tidak bisa dibayar dengan e-wallet sungguhan. Untuk simulasi bayar: buka simulator QRIS Midtrans, '
            'tempel URL gambar QR di bawah, lalu klik Pay. Status di sini akan berubah otomatis.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (qrUrl != null)
              ActionChip(
                avatar: const Icon(Icons.copy, size: 16),
                label: const Text('Salin URL QR'),
                onPressed: () => _copy(context, qrUrl!, 'URL QR'),
              ),
            ActionChip(
              avatar: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Salin link simulator'),
              onPressed: () => _copy(context, _simulatorUrl, 'Link simulator'),
            ),
          ]),
        ]),
      );
}
