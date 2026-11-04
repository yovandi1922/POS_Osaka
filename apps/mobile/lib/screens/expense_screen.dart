// apps/mobile/lib/screens/expense_screen.dart
// Form pilih kategori, jumlah, keterangan → insert expenses (kasir boleh insert, tidak boleh baca).
import 'package:coffee_core/coffee_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/auth_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ExpenseScreen extends StatefulWidget {
  const ExpenseScreen({super.key});

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _Submitted {
  const _Submitted(this.category, this.amount, this.description, this.at);
  final String category;
  final double amount;
  final String description;
  final DateTime at;
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  String _category = 'Operasional';
  final _amount = TextEditingController();
  final _description = TextEditingController();
  bool _saving = false;
  String? _error;
  String? _success;
  final List<_Submitted> _submitted = [];

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = parseMoney(_amount.text);
    if (value == null || value <= 0) {
      setState(() => _error = 'Jumlah harus lebih dari 0.');
      return;
    }
    final userId = context.read<AuthController>().userId;
    if (userId == null) {
      setState(() => _error = 'Sesi berakhir, silakan login ulang.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      await context.read<CoffeeRepository>().addExpense(
            userId: userId,
            category: _category,
            amount: value,
            description: _description.text,
          );
      if (!mounted) return;
      setState(() {
        _submitted.insert(0, _Submitted(_category, value, _description.text.trim(), DateTime.now()));
        if (_submitted.length > 10) _submitted.removeLast();
        _success = 'Pengeluaran ${formatRupiah(value)} ($_category) tersimpan.';
        _amount.clear();
        _description.clear();
      });
      FocusScope.of(context).unfocus();
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = parseMoney(_amount.text);
    return Scaffold(
      appBar: AppBar(title: const Text('Pengeluaran')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MessageBanner(message: _error),
          MessageBanner(message: _success, isError: false),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Kategori', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.muted)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in expenseCategories)
                        ChoiceChip(
                          label: Text(c),
                          selected: _category == c,
                          onSelected: (_) => setState(() => _category = c),
                          selectedColor: AppColors.primary,
                          showCheckmark: false,
                          labelStyle: TextStyle(color: _category == c ? Colors.white : AppColors.text, fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _amount,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    decoration: const InputDecoration(labelText: 'Jumlah', prefixText: 'Rp '),
                  ),
                  if (preview != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(formatRupiah(preview),
                          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _description,
                    maxLines: 3,
                    maxLength: 300,
                    decoration: const InputDecoration(labelText: 'Keterangan', hintText: 'Contoh: beli es batu & gas'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const SizedBox(
                            width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                        : const Text('Simpan pengeluaran'),
                  ),
                ],
              ),
            ),
          ),
          if (_submitted.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Dicatat di sesi ini', style: TextStyle(fontWeight: FontWeight.w800)),
                    for (final s in _submitted)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(s.category, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: s.description.isEmpty ? null : Text(s.description),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(formatRupiah(s.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text(formatTime(s.at), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
