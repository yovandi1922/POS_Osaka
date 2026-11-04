// apps/mobile/lib/screens/stock_screen.dart
// List bahan + input qty cepat + tombol "Masuk" (RPC adjust_stock type 'in').
import 'package:coffee_core/coffee_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/tab_nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/tab_refresh.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> with TabRefresh<StockScreen> {
  List<Ingredient> _items = [];
  final Map<String, TextEditingController> _inputs = {};
  String _search = '';
  String? _savingId;
  bool _loading = true;
  String? _error;

  @override
  AppTab get tab => AppTab.stok;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    for (final c in _inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String id) => _inputs.putIfAbsent(id, TextEditingController.new);

  @override
  Future<void> refresh() async {
    try {
      final items = await context.read<CoffeeRepository>().ingredients();
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _stockIn(Ingredient item) async {
    final qty = parseDecimal(_controllerFor(item.id).text);
    if (qty == null || qty <= 0) {
      showSnack(context, 'Isi jumlah stok masuk lebih dari 0.', error: true);
      return;
    }
    setState(() => _savingId = item.id);
    try {
      final updated = await context.read<CoffeeRepository>().adjustStock(item.id, 'in', qty, notes: 'Stok masuk (mobile)');
      if (!mounted) return;
      setState(() {
        _items = [for (final i in _items) i.id == item.id ? updated : i];
        _controllerFor(item.id).clear();
      });
      FocusScope.of(context).unfocus();
      showSnack(context, '${item.name} +${formatNumber(qty, maxFractionDigits: 3)} ${item.unit} tercatat');
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _savingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();
    final visible = (q.isEmpty ? _items : _items.where((i) => i.name.toLowerCase().contains(q)).toList())
      // Bahan menipis tampil paling atas.
      ..sort((a, b) {
        final byLow = (a.isLow ? 0 : 1) - (b.isLow ? 0 : 1);
        return byLow != 0 ? byLow : a.name.compareTo(b.name);
      });

    return Scaffold(
      appBar: AppBar(title: const Text('Stok Bahan')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              decoration: const InputDecoration(hintText: 'Cari bahan…', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: MessageBanner(message: _error)),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: refresh,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final item = visible[i];
                        final saving = _savingId == item.id;
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        Flexible(
                                          child: Text(item.name,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                        ),
                                        const SizedBox(width: 6),
                                        StatusBadge(item.status),
                                      ]),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${formatNumber(item.currentStock, maxFractionDigits: 3)} ${item.unit} · '
                                        'min ${formatNumber(item.minStock, maxFractionDigits: 3)}',
                                        style: const TextStyle(color: AppColors.muted, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 76,
                                  child: TextField(
                                    controller: _controllerFor(item.id),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    textAlign: TextAlign.center,
                                    decoration: const InputDecoration(
                                      hintText: 'Qty',
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.success,
                                    minimumSize: const Size(72, 42),
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                  ),
                                  onPressed: saving ? null : () => _stockIn(item),
                                  child: saving
                                      ? const SizedBox(
                                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Text('Masuk', style: TextStyle(fontSize: 14)),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
