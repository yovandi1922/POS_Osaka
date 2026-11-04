// apps/admin/lib/pages/expenses_page.dart
// Form tambah pengeluaran + tabel riwayat (100 terakhir).
import 'package:coffee_core/coffee_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/admin_session.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key});

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  List<Expense> _rows = [];
  bool _loading = true;
  String? _error;

  String _category = expenseCategories.first;
  final _amount = TextEditingController();
  final _description = TextEditingController();
  String _date = jakartaDate();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  CoffeeRepository get _repo => context.read<CoffeeRepository>();

  Future<void> _load() async {
    try {
      final rows = await _repo.recentExpenses(limit: 100);
      if (!mounted) return;
      setState(() {
        _rows = rows;
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

  Future<void> _pickDate() async {
    final current = DateTime.parse(_date);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime.parse(jakartaDate()),
    );
    if (picked != null) {
      setState(() => _date =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _submit() async {
    final value = parseMoney(_amount.text);
    if (value == null || value <= 0) return showSnack(context, 'Jumlah harus lebih dari 0.', error: true);
    final userId = context.read<AdminSession>().profile?.id;
    if (userId == null) return;
    setState(() => _saving = true);
    try {
      await _repo.addExpense(userId: userId, category: _category, amount: value, description: _description.text, expenseDate: _date);
      if (!mounted) return;
      showSnack(context, 'Pengeluaran tercatat.');
      _amount.clear();
      _description.clear();
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(Expense e) async {
    if (!await confirmDialog(context, 'Hapus pengeluaran', 'Hapus ${e.category} ${formatRupiah(e.amount)}?')) return;
    try {
      await _repo.deleteExpense(e.id);
      if (mounted) setState(() => _rows = _rows.where((r) => r.id != e.id).toList());
    } catch (err) {
      if (mounted) showSnack(context, errorText(err), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _rows.fold<double>(0, (s, r) => s + r.amount);
    return PageScaffold(
      title: 'Pengeluaran',
      subtitle: 'Catat biaya operasional dan lihat riwayat pengeluaran.',
      children: [
        NoticeBanner(message: _error),
        SectionCard(
          title: 'Catat pengeluaran',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Kategori'),
                  items: [for (final c in expenseCategories) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: (v) => setState(() => _category = v ?? _category),
                ),
              ),
              SizedBox(width: 180, child: TextField(controller: _amount, decoration: const InputDecoration(labelText: 'Jumlah', prefixText: 'Rp '))),
              OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.calendar_today, size: 16), label: Text(longDate(_date))),
              SizedBox(
                width: 320,
                child: TextField(controller: _description, decoration: const InputDecoration(labelText: 'Keterangan', hintText: 'Beli gas & es batu')),
              ),
            ]),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: _saving ? null : _submit, icon: const Icon(Icons.add, size: 18), label: const Text('Simpan')),
          ]),
        ),
        const SizedBox(height: 16),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                const Expanded(child: Text('Riwayat (100 terakhir)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                Text('Total: ${formatRupiah(total)}', style: const TextStyle(color: AppColors.muted)),
              ]),
            ),
            if (_loading)
              const LoadingBox()
            else if (_rows.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Belum ada pengeluaran.')))
            else
              ScrollTable(
                table: DataTable(
                  columns: const [
                    DataColumn(label: Text('TANGGAL')),
                    DataColumn(label: Text('KATEGORI')),
                    DataColumn(label: Text('KETERANGAN')),
                    DataColumn(label: Text('DICATAT OLEH')),
                    DataColumn(label: Text('JUMLAH'), numeric: true),
                    DataColumn(label: Text('')),
                  ],
                  rows: [
                    for (final e in _rows)
                      DataRow(cells: [
                        DataCell(Text(longDate(e.expenseDate))),
                        DataCell(Pill(e.category, fg: const Color(0xFF9A3412), bg: const Color(0xFFFFEDD5))),
                        DataCell(Text(e.description ?? '—')),
                        DataCell(Text(e.creatorName ?? '—')),
                        DataCell(Text(formatRupiah(e.amount), style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(IconButton(tooltip: 'Hapus', onPressed: () => _delete(e), icon: const Icon(Icons.delete_outline, size: 18))),
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
