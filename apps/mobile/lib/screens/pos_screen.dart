// apps/mobile/lib/screens/pos_screen.dart
// Chip kategori horizontal, grid menu 2 kolom, tap = tambah ke keranjang, footer sticky total + Bayar.
import 'package:coffee_core/coffee_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/cart.dart';
import '../state/tab_nav.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/tab_refresh.dart';
import 'checkout_screen.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> with TabRefresh<PosScreen> {
  List<MenuCategory> _categories = [];
  List<MenuItem> _items = [];
  String? _activeCategory; // null = semua
  bool _loading = true;
  String? _error;

  @override
  AppTab get tab => AppTab.kasir;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  Future<void> refresh() async {
    final repo = context.read<CoffeeRepository>();
    try {
      final results = await Future.wait([repo.categories(), repo.menuItems(activeOnly: true)]);
      if (!mounted) return;
      setState(() {
        _categories = results[0] as List<MenuCategory>;
        _items = results[1] as List<MenuItem>;
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

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<Cart>();
    final visible = _activeCategory == null ? _items : _items.where((i) => i.categoryId == _activeCategory).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Kasir')),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              children: [
                _chip('Semua', _activeCategory == null, () => setState(() => _activeCategory = null)),
                for (final c in _categories)
                  _chip(c.name, _activeCategory == c.id, () => setState(() => _activeCategory = c.id)),
              ],
            ),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: MessageBanner(message: _error)),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: refresh,
                    child: visible.isEmpty
                        ? ListView(children: const [
                            SizedBox(height: 80),
                            Center(child: Text('Tidak ada menu aktif di kategori ini.', style: TextStyle(color: AppColors.muted))),
                          ])
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 1.05,
                            ),
                            itemCount: visible.length,
                            itemBuilder: (_, i) => _MenuCard(item: visible[i], qty: cart.qtyOf(visible[i].id), onTap: () => cart.add(visible[i])),
                          ),
                  ),
          ),
          _Footer(
            count: cart.count,
            total: cart.total,
            onPay: cart.isEmpty
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CheckoutScreen())),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: active,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.primary,
        labelStyle: TextStyle(color: active ? Colors.white : AppColors.text, fontWeight: FontWeight.w600),
        showCheckmark: false,
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.item, required this.qty, required this.onTap});

  final MenuItem item;
  final int qty;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: qty > 0 ? AppColors.primary : AppColors.border, width: qty > 0 ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      item.name.isEmpty ? '?' : item.name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Text(item.name,
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                  Text(formatRupiah(item.price),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.primary)),
                ],
              ),
            ),
            if (qty > 0)
              Positioned(
                top: 8,
                right: 8,
                child: CircleAvatar(
                  radius: 13,
                  backgroundColor: AppColors.primary,
                  child: Text('$qty', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.count, required this.total, required this.onPay});

  final int count;
  final double total;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border))),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$count item', style: const TextStyle(color: AppColors.muted)),
                  Text(formatRupiah(total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            SizedBox(width: 150, child: FilledButton(onPressed: onPay, child: const Text('Bayar'))),
          ],
        ),
      ),
    );
  }
}
