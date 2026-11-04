// apps/admin/lib/pages/ingredients_page.dart
// Form tambah bahan + tabel stok dengan modal adjust (in / waste) + riwayat pergerakan stok.
import 'package:coffee_core/coffee_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme.dart';
import '../widgets/common.dart';

class IngredientsPage extends StatefulWidget {
  const IngredientsPage({super.key});

  @override
  State<IngredientsPage> createState() => _IngredientsPageState();
}

class _IngredientsPageState extends State<IngredientsPage> {
  List<Ingredient> _items = [];
  List<StockMovement> _moves = [];
  bool _loading = true;
  String? _error;
  String _search = '';

  final _name = TextEditingController();
  final _unit = TextEditingController(text: 'gram');
  final _stock = TextEditingController();
  final _min = TextEditingController();
  final _cost = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _unit, _stock, _min, _cost]) {
      c.dispose();
    }
    super.dispose();
  }

  CoffeeRepository get _repo => context.read<CoffeeRepository>();

  Future<void> _load() async {
    try {
      final r = await Future.wait([_repo.ingredients(), _repo.stockMovements(limit: 30)]);
      if (!mounted) return;
      setState(() {
        _items = r[0] as List<Ingredient>;
        _moves = r[1] as List<StockMovement>;
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

  Future<void> _add() async {
    final stock = _stock.text.trim().isEmpty ? 0.0 : parseDecimal(_stock.text);
    final min = _min.text.trim().isEmpty ? 0.0 : parseDecimal(_min.text);
    final cost = _cost.text.trim().isEmpty ? 0.0 : parseMoney(_cost.text);
    if (_name.text.trim().isEmpty || _unit.text.trim().isEmpty) {
      return showSnack(context, 'Nama dan satuan wajib diisi.', error: true);
    }
    if (stock == null || min == null || cost == null || stock < 0 || min < 0) {
      return showSnack(context, 'Angka tidak valid.', error: true);
    }
    try {
      await _repo.addIngredient(name: _name.text.trim(), unit: _unit.text.trim(), currentStock: stock, minStock: min, costPerUnit: cost);
      if (!mounted) return;
      showSnack(context, 'Bahan ditambahkan.');
      _name.clear();
      _stock.clear();
      _min.clear();
      _cost.clear();
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), error: true);
    }
  }

  Future<void> _adjust(Ingredient item) async {
    final changed = await showDialog<bool>(context: context, builder: (_) => _AdjustDialog(item: item, repo: _repo));
    if (changed == true) {
      if (mounted) showSnack(context, 'Penyesuaian stok ${item.name} tercatat.');
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();
    final visible = q.isEmpty ? _items : _items.where((i) => i.name.toLowerCase().contains(q)).toList();
    final lowCount = _items.where((i) => i.isLow).length;
    final stockValue = _items.fold<double>(0, (s, i) => s + (i.currentStock > 0 ? i.currentStock : 0) * i.costPerUnit);

    return PageScaffold(
      title: 'Stok Bahan',
      subtitle: 'Tambah bahan baku, pantau stok minimum, dan catat stok masuk / terbuang.',
      children: [
        NoticeBanner(message: _error),
        SectionCard(
          title: 'Tambah bahan baku',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 12, runSpacing: 12, children: [
              SizedBox(width: 240, child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nama bahan', hintText: 'Susu Oat'))),
              SizedBox(width: 120, child: TextField(controller: _unit, decoration: const InputDecoration(labelText: 'Satuan'))),
              SizedBox(width: 130, child: TextField(controller: _stock, decoration: const InputDecoration(labelText: 'Stok awal'))),
              SizedBox(width: 130, child: TextField(controller: _min, decoration: const InputDecoration(labelText: 'Stok minimum'))),
              SizedBox(width: 170, child: TextField(controller: _cost, decoration: const InputDecoration(labelText: 'Harga / satuan', prefixText: 'Rp '))),
            ]),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add, size: 18), label: const Text('Simpan bahan')),
          ]),
        ),
        const SizedBox(height: 16),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  Text('${_items.length} bahan · $lowCount menipis · nilai stok ${formatRupiah(stockValue)}',
                      style: const TextStyle(color: AppColors.muted)),
                  SizedBox(
                    width: 260,
                    child: TextField(
                      decoration: const InputDecoration(hintText: 'Cari bahan…', prefixIcon: Icon(Icons.search, size: 18)),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                  ),
                ],
              ),
            ),
            if (_loading)
              const LoadingBox()
            else
              ScrollTable(
                table: DataTable(
                  columns: const [
                    DataColumn(label: Text('BAHAN')),
                    DataColumn(label: Text('STOK'), numeric: true),
                    DataColumn(label: Text('MINIMUM'), numeric: true),
                    DataColumn(label: Text('HARGA/SATUAN'), numeric: true),
                    DataColumn(label: Text('STATUS')),
                    DataColumn(label: Text('')),
                  ],
                  rows: [
                    for (final i in visible)
                      DataRow(cells: [
                        DataCell(Text(i.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Text('${formatNumber(i.currentStock, maxFractionDigits: 3)} ${i.unit}')),
                        DataCell(Text('${formatNumber(i.minStock, maxFractionDigits: 3)} ${i.unit}',
                            style: const TextStyle(color: AppColors.muted))),
                        DataCell(Text(formatRupiah(i.costPerUnit))),
                        DataCell(stockPill(i.status)),
                        DataCell(OutlinedButton.icon(
                          onPressed: () => _adjust(i),
                          icon: const Icon(Icons.tune, size: 16),
                          label: const Text('Adjust'),
                        )),
                      ]),
                  ],
                ),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Riwayat pergerakan stok (30 terakhir)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            if (_moves.isEmpty && !_loading)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Belum ada pergerakan stok.')))
            else
              ScrollTable(
                table: DataTable(
                  columns: const [
                    DataColumn(label: Text('WAKTU (WIB)')),
                    DataColumn(label: Text('BAHAN')),
                    DataColumn(label: Text('TIPE')),
                    DataColumn(label: Text('QTY'), numeric: true),
                    DataColumn(label: Text('CATATAN')),
                  ],
                  rows: [
                    for (final m in _moves)
                      DataRow(cells: [
                        DataCell(Text(formatDateTime(m.createdAt))),
                        DataCell(Text(m.ingredientName ?? '—')),
                        DataCell(switch (m.type) {
                          'in' => const Pill('Masuk', fg: AppColors.success, bg: AppColors.successSoft),
                          'waste' => const Pill('Terbuang', fg: AppColors.danger, bg: AppColors.dangerSoft),
                          _ => const Pill('Terpakai', fg: AppColors.info, bg: AppColors.infoSoft),
                        }),
                        DataCell(Text('${m.type == 'in' ? '+' : '−'}${formatNumber(m.qty, maxFractionDigits: 3)} ${m.unit ?? ''}')),
                        DataCell(Text(m.notes ?? '—', style: const TextStyle(color: AppColors.muted))),
                      ]),
                  ],
                ),
              ),
          ]),
        ),
      ],
    );
  }
}

class _AdjustDialog extends StatefulWidget {
  const _AdjustDialog({required this.item, required this.repo});

  final Ingredient item;
  final CoffeeRepository repo;

  @override
  State<_AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<_AdjustDialog> {
  String _type = 'in';
  final _qty = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _qty.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final qty = parseDecimal(_qty.text);
    if (qty == null || qty <= 0) return setState(() => _error = 'Qty harus lebih dari 0.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repo.adjustStock(widget.item.id, _type, qty, notes: _notes.text.trim().isEmpty ? null : _notes.text.trim());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return AlertDialog(
      title: Text('Adjust stok: ${item.name}'),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Stok saat ini ${formatNumber(item.currentStock, maxFractionDigits: 3)} ${item.unit}',
              style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 12),
          NoticeBanner(message: _error),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'in', label: Text('Stok masuk'), icon: Icon(Icons.add_box_outlined)),
              ButtonSegment(value: 'waste', label: Text('Terbuang / rusak'), icon: Icon(Icons.delete_outline)),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 12),
          TextField(controller: _qty, autofocus: true, decoration: InputDecoration(labelText: 'Qty (${item.unit})')),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: InputDecoration(labelText: 'Catatan', hintText: _type == 'in' ? 'Belanja supplier' : 'Susu basi'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Batal')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _type == 'in' ? AppColors.coffee700 : AppColors.danger),
          onPressed: _busy ? null : _save,
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
