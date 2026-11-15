// apps/admin/lib/pages/ingredients_page.dart
// Form tambah bahan + tabel stok dengan modal adjust (in / waste), hapus bahan, + riwayat pergerakan stok.
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
  final _price = TextEditingController();
  final _pack = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _unit, _stock, _min, _price, _pack]) {
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
    final cost = _unitCostFrom(_price.text, _pack.text);
    if (_name.text.trim().isEmpty || _unit.text.trim().isEmpty) {
      return showSnack(context, 'Nama dan satuan wajib diisi.', error: true);
    }
    if (stock == null || stock < 0) return showSnack(context, 'Stok awal tidak valid.', error: true);
    if (min == null || min < 0) return showSnack(context, 'Stok minimum tidak valid.', error: true);
    if (cost == null) return showSnack(context, 'Harga beli / isi kemasan tidak valid.', error: true);
    setState(() => _saving = true);
    try {
      await _repo.addIngredient(name: _name.text.trim(), unit: _unit.text.trim(), currentStock: stock, minStock: min, costPerUnit: cost);
      if (!mounted) return;
      showSnack(context, 'Bahan ditambahkan.');
      for (final c in [_name, _stock, _min, _price, _pack]) {
        c.clear();
      }
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _adjust(Ingredient item) async {
    final changed = await showDialog<bool>(context: context, builder: (_) => _AdjustDialog(item: item, repo: _repo));
    if (changed == true) {
      if (mounted) showSnack(context, 'Penyesuaian stok ${item.name} tercatat.');
      await _load();
    }
  }

  Future<void> _edit(Ingredient item) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _EditDialog(item: item, repo: _repo));
    if (saved != true) return;
    if (mounted) showSnack(context, 'Bahan diperbarui.');
    await _load();
  }

  Future<void> _delete(Ingredient item) async {
    try {
      final r = await Future.wait([_repo.menuItems(), _repo.recipes()]);
      final menus = r[0] as List<MenuItem>;
      final recipes = r[1] as List<Recipe>;
      final usedBy = {for (final rc in recipes.where((rc) => rc.ingredientId == item.id)) rc.menuItemId};
      final menuNames = menus.where((m) => usedBy.contains(m.id)).map((m) => m.name).toList();
      if (!mounted) return;

      final ok = await confirmDialog(
        context,
        'Hapus bahan "${item.name}"?',
        [
          if (menuNames.isNotEmpty)
            'Bahan ini dipakai di resep: ${menuNames.join(', ')}. '
                'Bahan akan dikeluarkan dari resep tersebut dan HPP-nya dihitung ulang.',
          'Riwayat pergerakan stok bahan ini juga ikut terhapus. Aksi ini tidak bisa dibatalkan.',
        ].join('\n\n'),
      );
      if (!ok) return;

      await _repo.deleteIngredient(item.id);
      if (usedBy.isNotEmpty) {
        final fresh = await Future.wait([_repo.recipes(), _repo.ingredients()]);
        await _repo.syncMenuCosts(
          menus.where((m) => usedBy.contains(m.id)).toList(),
          fresh[0] as List<Recipe>,
          fresh[1] as List<Ingredient>,
        );
      }
      if (mounted) showSnack(context, 'Bahan ${item.name} dihapus.');
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), error: true);
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
              SizedBox(width: 150, child: _UnitField(controller: _unit)),
              SizedBox(width: 150, child: _QtyField(controller: _stock, unit: _unit, label: 'Stok awal')),
              SizedBox(width: 150, child: _QtyField(controller: _min, unit: _unit, label: 'Stok minimum')),
            ]),
            const SizedBox(height: 12),
            _PriceFields(price: _price, pack: _pack, unit: _unit),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _add,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Simpan bahan'),
            ),
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
                        DataCell(Text('${formatRupiahPrecise(i.costPerUnit)} / ${i.unit}')),
                        DataCell(stockPill(i.status)),
                        DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                          OutlinedButton.icon(
                            onPressed: () => _adjust(i),
                            icon: const Icon(Icons.tune, size: 16),
                            label: const Text('Adjust'),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: 'Ubah bahan',
                            onPressed: () => _edit(i),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                          ),
                          IconButton(
                            tooltip: 'Hapus bahan',
                            onPressed: () => _delete(i),
                            icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
                          ),
                        ])),
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

/// Harga per satuan = harga beli ÷ isi kemasan (isi kosong = 1), dibulatkan 2 desimal.
/// Harga kosong = 0. Mengembalikan null bila input tidak valid.
double? _unitCostFrom(String price, String pack) {
  final p = price.trim().isEmpty ? 0.0 : parseMoney(price);
  final n = pack.trim().isEmpty ? 1.0 : parseDecimal(pack);
  if (p == null || n == null || n <= 0) return null;
  return (p / n * 100).roundToDouble() / 100;
}

const _commonUnits = ['gram', 'kg', 'ml', 'liter', 'pcs', 'lembar', 'sachet', 'botol'];

/// Satuan dasar dengan pilihan cepat; tetap bisa diketik bebas.
class _UnitField extends StatelessWidget {
  const _UnitField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: 'Satuan',
          suffixIcon: PopupMenuButton<String>(
            tooltip: 'Pilih satuan',
            icon: const Icon(Icons.arrow_drop_down),
            onSelected: (u) => controller.text = u,
            itemBuilder: (_) => [for (final u in _commonUnits) PopupMenuItem(value: u, child: Text(u))],
          ),
        ),
      );
}

/// Input jumlah yang menampilkan satuan aktif di belakangnya.
class _QtyField extends StatelessWidget {
  const _QtyField({required this.controller, required this.unit, required this.label});

  final TextEditingController controller;
  final TextEditingController unit;
  final String label;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: unit,
        builder: (_, _) => TextField(
          controller: controller,
          decoration: InputDecoration(labelText: label, suffixText: unit.text.trim()),
        ),
      );
}

/// Harga beli per kemasan + isi kemasan → pratinjau harga per satuan (yang dipakai menghitung HPP).
class _PriceFields extends StatelessWidget {
  const _PriceFields({required this.price, required this.pack, required this.unit});

  final TextEditingController price;
  final TextEditingController pack;
  final TextEditingController unit;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([price, pack, unit]),
        builder: (_, _) {
          final u = unit.text.trim().isEmpty ? 'satuan' : unit.text.trim();
          final cost = _unitCostFrom(price.text, pack.text);
          return Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 190,
              child: TextField(
                controller: price,
                decoration: const InputDecoration(labelText: 'Harga beli', prefixText: 'Rp ', hintText: '18.000'),
              ),
            ),
            SizedBox(
              width: 190,
              child: TextField(
                controller: pack,
                decoration: InputDecoration(labelText: 'Isi per kemasan', hintText: '1', suffixText: u),
              ),
            ),
            Text(
              cost == null ? 'Isi kemasan harus > 0' : '= ${formatRupiahPrecise(cost)} / $u',
              style: TextStyle(fontWeight: FontWeight.w700, color: cost == null ? AppColors.danger : AppColors.coffee700),
            ),
          ]);
        },
      );
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.item, required this.repo});

  final Ingredient item;
  final CoffeeRepository repo;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _name = TextEditingController(text: widget.item.name);
  late final _unit = TextEditingController(text: widget.item.unit);
  late final _min = TextEditingController(text: formatNumber(widget.item.minStock, maxFractionDigits: 3));
  // Harga per satuan lama tampil sebagai "harga beli" dengan isi 1 → hasilnya sama persis.
  // parseMoney mengabaikan desimal, jadi harga berdesimal (mis. 18,95/ml) diisi via harga kemasan.
  late final _price = TextEditingController(text: formatNumber(widget.item.costPerUnit.round()));
  final _pack = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _unit, _min, _price, _pack]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final unit = _unit.text.trim();
    final min = _min.text.trim().isEmpty ? 0.0 : parseDecimal(_min.text);
    final priceUnchanged = _price.text == formatNumber(widget.item.costPerUnit.round()) && _pack.text.trim().isEmpty;
    // Jangan bulatkan harga lama yang berdesimal bila user tidak menyentuh kolom harga.
    final cost = priceUnchanged ? widget.item.costPerUnit : _unitCostFrom(_price.text, _pack.text);
    if (name.isEmpty || unit.isEmpty) return setState(() => _error = 'Nama dan satuan wajib diisi.');
    if (min == null || min < 0) return setState(() => _error = 'Stok minimum tidak valid.');
    if (cost == null) return setState(() => _error = 'Harga beli / isi kemasan tidak valid.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = widget.repo;
      await repo.updateIngredient(widget.item.id, name: name, unit: unit, minStock: min, costPerUnit: cost);
      // Harga bahan berubah → HPP menu yang memakainya ikut dihitung ulang.
      if ((cost - widget.item.costPerUnit).abs() >= 0.005) {
        final r = await Future.wait([repo.menuItems(), repo.recipes(), repo.ingredients()]);
        await repo.syncMenuCosts(r[0] as List<MenuItem>, r[1] as List<Recipe>, r[2] as List<Ingredient>);
      }
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
      title: Text('Ubah bahan: ${item.name}'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          NoticeBanner(message: _error),
          TextField(controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'Nama bahan')),
          const SizedBox(height: 12),
          _UnitField(controller: _unit),
          const Padding(
            padding: EdgeInsets.only(top: 4, left: 12),
            child: Text('Takaran resep & stok memakai satuan ini — sesuaikan bila satuannya diganti.',
                style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ),
          const SizedBox(height: 12),
          _QtyField(controller: _min, unit: _unit, label: 'Stok minimum'),
          const SizedBox(height: 16),
          Text('Harga sekarang ${formatRupiahPrecise(item.costPerUnit)} / ${item.unit}',
              style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 8),
          _PriceFields(price: _price, pack: _pack, unit: _unit),
          const SizedBox(height: 4),
          const Text('HPP menu yang memakai bahan ini dihitung ulang otomatis.',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 12),
          Text(
            'Stok saat ini ${formatNumber(item.currentStock, maxFractionDigits: 3)} ${item.unit} — '
            'ubah lewat tombol Adjust agar tercatat di riwayat.',
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Batal')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Simpan')),
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
