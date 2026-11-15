// apps/admin/lib/pages/menu_page.dart
// Form tambah menu + tabel dengan toggle aktif, ubah harga, kategori, dan editor resep.
// Resep menentukan potong stok otomatis saat checkout DAN HPP (Σ takaran × harga/satuan bahan).
import 'package:coffee_core/coffee_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme.dart';
import '../widgets/common.dart';

class MenuPage extends StatefulWidget {
  const MenuPage({super.key});

  @override
  State<MenuPage> createState() => _MenuPageState();
}

class _MenuPageState extends State<MenuPage> {
  List<MenuCategory> _categories = [];
  List<MenuItem> _items = [];
  List<Ingredient> _ingredients = [];
  List<Recipe> _recipes = [];
  bool _loading = true;
  String? _error;

  final _name = TextEditingController();
  final _price = TextEditingController();
  final _imageUrl = TextEditingController();
  final _newCategory = TextEditingController();
  String? _categoryId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _price, _imageUrl, _newCategory]) {
      c.dispose();
    }
    super.dispose();
  }

  CoffeeRepository get _repo => context.read<CoffeeRepository>();

  Future<void> _load() async {
    try {
      final r = await Future.wait([_repo.categories(), _repo.menuItems(), _repo.ingredients(), _repo.recipes()]);
      var items = r[1] as List<MenuItem>;
      final ingredients = r[2] as List<Ingredient>;
      final recipes = r[3] as List<Recipe>;
      // HPP selalu mengikuti resep × harga bahan terbaru.
      String? syncError;
      try {
        if (await _repo.syncMenuCosts(items, recipes, ingredients) > 0) items = await _repo.menuItems();
      } catch (e) {
        syncError = errorText(e);
      }
      if (!mounted) return;
      setState(() {
        _categories = r[0] as List<MenuCategory>;
        _items = items;
        _ingredients = ingredients;
        _recipes = recipes;
        _error = syncError;
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

  Future<void> _run(Future<void> Function() action, String success) async {
    try {
      await action();
      if (mounted) showSnack(context, success);
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), error: true);
    }
  }

  Future<void> _addMenu() async {
    final price = parseMoney(_price.text);
    if (_name.text.trim().isEmpty) return showSnack(context, 'Nama menu wajib diisi.', error: true);
    if (price == null) return showSnack(context, 'Harga tidak valid.', error: true);
    setState(() => _saving = true);
    await _run(
      () => _repo.addMenuItem(
        name: _name.text.trim(),
        categoryId: _categoryId,
        price: price,
        cost: 0, // dihitung otomatis setelah resep diisi
        imageUrl: _imageUrl.text.trim().isEmpty ? null : _imageUrl.text.trim(),
      ),
      'Menu ditambahkan. Isi resepnya: HPP dihitung otomatis dan stok terpotong saat terjual.',
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _name.clear();
      _price.clear();
      _imageUrl.clear();
    });
  }

  Future<void> _addCategory() async {
    final name = _newCategory.text.trim();
    if (name.isEmpty) return;
    final sort = _categories.fold<int>(0, (m, c) => c.sortOrder > m ? c.sortOrder : m) + 1;
    await _run(() => _repo.addCategory(name, sort), 'Kategori ditambahkan.');
    _newCategory.clear();
  }

  Future<void> _toggle(MenuItem item, bool value) async {
    setState(() => _items = [for (final m in _items) m.id == item.id ? m.copyWith(isActive: value) : m]);
    try {
      await _repo.updateMenuItem(item.id, isActive: value);
    } catch (e) {
      if (!mounted) return;
      setState(() => _items = [for (final m in _items) m.id == item.id ? item : m]);
      showSnack(context, errorText(e), error: true);
    }
  }

  bool _hasRecipe(MenuItem item) => _recipes.any((r) => r.menuItemId == item.id);

  Future<void> _editPrice(MenuItem item) async {
    final price = TextEditingController(text: item.price.round().toString());
    final hasRecipe = _hasRecipe(item);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ubah harga: ${item.name}'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: price, decoration: const InputDecoration(labelText: 'Harga jual', prefixText: 'Rp ')),
            const SizedBox(height: 12),
            Text(
              hasRecipe
                  ? 'HPP ${formatRupiah(item.cost)} — dihitung otomatis dari resep.'
                  : 'HPP belum bisa dihitung: menu ini belum punya resep.',
              style: const TextStyle(color: AppColors.muted),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
        ],
      ),
    );
    final p = parseMoney(price.text);
    price.dispose();
    if (ok != true) return;
    if (p == null) {
      if (mounted) showSnack(context, 'Harga tidak valid.', error: true);
      return;
    }
    await _run(() => _repo.updateMenuItem(item.id, price: p), 'Harga diperbarui.');
  }

  Future<void> _editRecipe(MenuItem item) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _RecipeDialog(
        item: item,
        ingredients: _ingredients,
        initial: _recipes.where((r) => r.menuItemId == item.id).toList(),
        repo: _repo,
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final categoryName = {for (final c in _categories) c.id: c.name};
    return PageScaffold(
      title: 'Menu',
      subtitle: 'Tambah menu, atur harga, aktif/nonaktifkan, dan kelola resep untuk potong stok otomatis.',
      children: [
        NoticeBanner(message: _error),
        ResponsiveRow(flex: const [2, 1], children: [
          SectionCard(
            title: 'Tambah menu',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 12, runSpacing: 12, children: [
                SizedBox(width: 260, child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nama menu', hintText: 'Es Kopi Susu'))),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: _categoryId,
                    decoration: const InputDecoration(labelText: 'Kategori'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('— Tanpa kategori —')),
                      for (final c in _categories) DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                ),
                SizedBox(width: 160, child: TextField(controller: _price, decoration: const InputDecoration(labelText: 'Harga jual', prefixText: 'Rp '))),
                SizedBox(width: 380, child: TextField(controller: _imageUrl, decoration: const InputDecoration(labelText: 'URL gambar (opsional)'))),
              ]),
              const SizedBox(height: 8),
              const Text('HPP dihitung otomatis dari resep (takaran × harga/satuan bahan).',
                  style: TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _addMenu,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Simpan menu'),
                ),
              ),
            ]),
          ),
          SectionCard(
            title: 'Kategori',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final c in _categories) Pill(c.name, fg: AppColors.coffee700, bg: AppColors.coffee100),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(controller: _newCategory, decoration: const InputDecoration(hintText: 'Kategori baru'))),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _addCategory, child: const Icon(Icons.add, size: 18)),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        Card(
          clipBehavior: Clip.antiAlias,
          child: _loading
              ? const LoadingBox()
              : ScrollTable(
                  table: DataTable(
                    columns: const [
                      DataColumn(label: Text('MENU')),
                      DataColumn(label: Text('KATEGORI')),
                      DataColumn(label: Text('HARGA'), numeric: true),
                      DataColumn(label: Text('HPP'), numeric: true),
                      DataColumn(label: Text('MARGIN'), numeric: true),
                      DataColumn(label: Text('RESEP')),
                      DataColumn(label: Text('AKTIF')),
                      DataColumn(label: Text('')),
                    ],
                    rows: [
                      for (final item in _items)
                        DataRow(
                          color: WidgetStatePropertyAll(item.isActive ? null : const Color(0xFFFAFAF9)),
                          cells: [
                            DataCell(Text(item.name,
                                style: TextStyle(fontWeight: FontWeight.w600, color: item.isActive ? AppColors.text : AppColors.muted))),
                            DataCell(Text(categoryName[item.categoryId] ?? '—')),
                            DataCell(Text(formatRupiah(item.price))),
                            DataCell(_hasRecipe(item)
                                ? Text(formatRupiah(item.cost))
                                : const Tooltip(message: 'Isi resep untuk menghitung HPP', child: Text('—', style: TextStyle(color: AppColors.muted)))),
                            DataCell(Text(_hasRecipe(item) && item.price > 0
                                ? '${((item.price - item.cost) / item.price * 100).round()}%'
                                : '—')),
                            DataCell(
                              Builder(builder: (_) {
                                final n = _recipes.where((r) => r.menuItemId == item.id).length;
                                return n > 0
                                    ? Pill('$n bahan', fg: AppColors.text, bg: const Color(0xFFF5F5F4))
                                    : const Pill('Belum ada', fg: AppColors.warning, bg: AppColors.warningSoft);
                              }),
                              onTap: () => _editRecipe(item),
                            ),
                            DataCell(Switch(value: item.isActive, onChanged: (v) => _toggle(item, v))),
                            DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(tooltip: 'Ubah harga', onPressed: () => _editPrice(item), icon: const Icon(Icons.edit_outlined, size: 18)),
                              IconButton(tooltip: 'Kelola resep', onPressed: () => _editRecipe(item), icon: const Icon(Icons.science_outlined, size: 18)),
                            ])),
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

class _RecipeDialog extends StatefulWidget {
  const _RecipeDialog({required this.item, required this.ingredients, required this.initial, required this.repo});

  final MenuItem item;
  final List<Ingredient> ingredients;
  final List<Recipe> initial;
  final CoffeeRepository repo;

  @override
  State<_RecipeDialog> createState() => _RecipeDialogState();
}

class _RecipeDialogState extends State<_RecipeDialog> {
  late List<Recipe> _rows = widget.initial;
  String? _ingredientId;
  final _qty = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final all = await widget.repo.recipes();
    if (mounted) setState(() => _rows = all.where((r) => r.menuItemId == widget.item.id).toList());
  }

  Future<void> _add() async {
    final qty = parseDecimal(_qty.text);
    if (_ingredientId == null) return setState(() => _error = 'Pilih bahan.');
    if (qty == null || qty <= 0) return setState(() => _error = 'Takaran harus > 0.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repo.upsertRecipe(widget.item.id, _ingredientId!, qty);
      _qty.clear();
      await _reload();
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(Recipe r) async {
    try {
      await widget.repo.deleteRecipe(r.id);
      await _reload();
    } catch (e) {
      setState(() => _error = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final byId = {for (final i in widget.ingredients) i.id: i};
    final hpp = recipeCost(widget.item.id, _rows, byId);
    return AlertDialog(
      title: Text('Resep per porsi: ${widget.item.name}'),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          NoticeBanner(message: _error),
          if (_rows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Belum ada bahan. Stok tidak akan terpotong saat menu ini terjual.', style: TextStyle(color: AppColors.muted)),
            ),
          for (final r in _rows)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(byId[r.ingredientId]?.name ?? 'Bahan dihapus'),
              subtitle: Text('${formatNumber(r.qtyNeeded, maxFractionDigits: 3)} ${byId[r.ingredientId]?.unit ?? ''}'
                  ' × ${formatRupiahPrecise(byId[r.ingredientId]?.costPerUnit ?? 0)}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(formatRupiah(r.qtyNeeded * (byId[r.ingredientId]?.costPerUnit ?? 0))),
                IconButton(tooltip: 'Hapus', onPressed: () => _remove(r), icon: const Icon(Icons.delete_outline, size: 18)),
              ]),
            ),
          if (hpp != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4, right: 48),
              child: Row(children: [
                const Expanded(child: Text('HPP per porsi', style: TextStyle(fontWeight: FontWeight.w700))),
                Text(formatRupiah(hpp), style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
          const Divider(),
          Row(children: [
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _ingredientId,
                decoration: const InputDecoration(labelText: 'Bahan'),
                items: [for (final i in widget.ingredients) DropdownMenuItem(value: i.id, child: Text('${i.name} (${i.unit})'))],
                onChanged: (v) => setState(() => _ingredientId = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: TextField(controller: _qty, decoration: const InputDecoration(labelText: 'Takaran'))),
          ]),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(onPressed: _busy ? null : _add, icon: const Icon(Icons.add, size: 18), label: const Text('Tambah / perbarui')),
          ),
        ]),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Selesai'))],
    );
  }
}
