// apps/admin/lib/pages/users_page.dart
// Tabel semua profiles. Owner dapat menambah, mengubah (nama/email/password/role), dan menghapus akun
// via apps/api /api/users (butuh service role di server).
import 'package:coffee_core/coffee_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/admin_session.dart';
import '../theme.dart';
import '../widgets/common.dart';

class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  List<Profile> _rows = [];
  bool _loading = true;
  String? _error;

  final _email = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  UserRole _role = UserRole.kasir;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await context.read<CoffeeRepository>().listProfiles();
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

  Future<void> _changeRole(Profile p, UserRole role) async {
    try {
      await context.read<CoffeeRepository>().updateRole(p.id, role);
      if (mounted) showSnack(context, 'Role ${p.displayName} → ${role.label}.');
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), error: true);
    }
  }

  Future<void> _edit(Profile p, {required bool isMe}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditUserDialog(profile: p, isMe: isMe, api: context.read<CoffeeApi>()),
    );
    if (saved != true) return;
    if (mounted) showSnack(context, 'Akun ${p.displayName} diperbarui.');
    await _load();
    // Bila owner mengubah nama/email miliknya sendiri, segarkan header sesi.
    if (isMe && mounted) await context.read<AdminSession>().refreshProfile();
  }

  Future<void> _delete(Profile p) async {
    final ok = await confirmDialog(
      context,
      'Hapus akun ${p.displayName}?',
      '${p.email} tidak akan bisa login lagi dan riwayat chat-nya ikut terhapus.\n\n'
          'Transaksi dan pengeluaran yang pernah dicatat tetap tersimpan, tanpa nama kasir. '
          'Aksi ini tidak bisa dibatalkan.',
    );
    if (!ok || !mounted) return;
    try {
      await context.read<CoffeeApi>().deleteUser(p.id);
      if (mounted) showSnack(context, 'Akun ${p.displayName} dihapus.');
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), error: true);
    }
  }

  Future<void> _create() async {
    if (_password.text.length < 8) return showSnack(context, 'Password minimal 8 karakter.', error: true);
    setState(() => _creating = true);
    try {
      await context.read<CoffeeApi>().createUser(
            email: _email.text.trim(),
            password: _password.text,
            name: _name.text.trim(),
            role: _role.name,
          );
      if (!mounted) return;
      showSnack(context, 'Pengguna dibuat. Bagikan email & password ke staff terkait.');
      _email.clear();
      _name.clear();
      _password.clear();
      setState(() => _role = UserRole.kasir);
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AdminSession>();
    final canEdit = session.isOwner;
    final me = session.profile?.id;

    return PageScaffold(
      title: 'Pengguna',
      subtitle: '${_rows.length} akun terdaftar. '
          '${canEdit ? 'Sebagai owner Anda dapat menambah akun dan mengubah role.' : 'Hanya owner yang dapat mengubah role.'}',
      children: [
        NoticeBanner(message: _error),
        if (canEdit) ...[
          SectionCard(
            title: 'Tambah pengguna',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 12, runSpacing: 12, children: [
                SizedBox(width: 200, child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nama'))),
                SizedBox(width: 240, child: TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email'))),
                SizedBox(
                  width: 200,
                  child: TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Password (min. 8)')),
                ),
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<UserRole>(
                    isExpanded: true,
                    initialValue: _role,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: [for (final r in UserRole.values) DropdownMenuItem(value: r, child: Text(r.label))],
                    onChanged: (v) => setState(() => _role = v ?? UserRole.kasir),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _creating ? null : _create,
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: const Text('Buat akun'),
              ),
            ]),
          ),
          const SizedBox(height: 16),
        ],
        Card(
          clipBehavior: Clip.antiAlias,
          child: _loading
              ? const LoadingBox()
              : ScrollTable(
                  table: DataTable(
                    columns: [
                      const DataColumn(label: Text('NAMA')),
                      const DataColumn(label: Text('EMAIL')),
                      const DataColumn(label: Text('ROLE')),
                      const DataColumn(label: Text('TERDAFTAR')),
                      if (canEdit) const DataColumn(label: Text('')),
                    ],
                    rows: [
                      for (final p in _rows)
                        DataRow(cells: [
                          DataCell(Text('${p.name ?? '—'}${p.id == me ? ' (Anda)' : ''}', style: const TextStyle(fontWeight: FontWeight.w600))),
                          DataCell(Text(p.email)),
                          DataCell(canEdit && p.id != me
                              ? DropdownButton<UserRole>(
                                  value: p.role,
                                  underline: const SizedBox.shrink(),
                                  items: [for (final r in UserRole.values) DropdownMenuItem(value: r, child: Text(r.label))],
                                  onChanged: (r) {
                                    if (r != null && r != p.role) _changeRole(p, r);
                                  },
                                )
                              : Pill(
                                  p.role.label,
                                  fg: switch (p.role) { UserRole.owner => AppColors.coffee700, UserRole.admin => AppColors.info, UserRole.kasir => AppColors.text },
                                  bg: switch (p.role) {
                                    UserRole.owner => AppColors.coffee100,
                                    UserRole.admin => AppColors.infoSoft,
                                    UserRole.kasir => const Color(0xFFF5F5F4),
                                  },
                                )),
                          DataCell(Text(formatDateTime(p.createdAt))),
                          if (canEdit)
                            DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(
                                tooltip: 'Ubah akun',
                                onPressed: () => _edit(p, isMe: p.id == me),
                                icon: const Icon(Icons.edit_outlined, size: 18),
                              ),
                              IconButton(
                                tooltip: p.id == me ? 'Tidak bisa menghapus akun sendiri' : 'Hapus akun',
                                onPressed: p.id == me ? null : () => _delete(p),
                                icon: Icon(Icons.delete_outline, size: 18, color: p.id == me ? null : AppColors.danger),
                              ),
                            ])),
                        ]),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _EditUserDialog extends StatefulWidget {
  const _EditUserDialog({required this.profile, required this.isMe, required this.api});

  final Profile profile;
  final bool isMe;
  final CoffeeApi api;

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  late final _name = TextEditingController(text: widget.profile.name ?? '');
  late final _email = TextEditingController(text: widget.profile.email);
  final _password = TextEditingController();
  late UserRole _role = widget.profile.role;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return setState(() => _error = 'Nama wajib diisi.');
    if (_password.text.isNotEmpty && _password.text.length < 8) {
      return setState(() => _error = 'Password baru minimal 8 karakter.');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = widget.profile;
      await widget.api.updateUser(
        p.id,
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        role: widget.isMe ? null : _role.name,
      );
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
    return AlertDialog(
      title: Text('Ubah akun: ${widget.profile.displayName}'),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          NoticeBanner(message: _error),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nama')),
          const SizedBox(height: 12),
          TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password baru', helperText: 'Kosongkan jika tidak diganti (min. 8 karakter)'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<UserRole>(
            isExpanded: true,
            initialValue: _role,
            decoration: InputDecoration(
              labelText: 'Role',
              helperText: widget.isMe ? 'Role akun sendiri tidak bisa diubah' : null,
            ),
            items: [for (final r in UserRole.values) DropdownMenuItem(value: r, child: Text(r.label))],
            onChanged: widget.isMe ? null : (v) => setState(() => _role = v ?? _role),
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
