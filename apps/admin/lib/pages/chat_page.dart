// apps/admin/lib/pages/chat_page.dart
// Asisten "Kopi" untuk owner/admin — sama seperti mobile, channel 'web' (jawaban boleh sedikit lebih panjang).
import 'package:coffee_core/coffee_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/admin_session.dart';
import '../theme.dart';
import '../widgets/common.dart';

class _Msg {
  _Msg(this.id, this.role, this.content, {this.pending = false});
  final String id;
  final String role;
  String content;
  bool pending;
  bool error = false;
}

const _suggestions = [
  'Berapa omset hari ini?',
  'Bahan apa saja yang stoknya menipis?',
  'Menu apa yang paling laku dan paling jarang laku minggu ini?',
  'Berapa laba kotor 30 hari terakhir?',
  'Prediksi omset 7 hari ke depan',
];
const _contextMessages = 12;

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<_Msg> _messages = [];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  bool _sending = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    _loadHistory();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final rows = await context.read<CoffeeRepository>().chatHistory();
      if (mounted) setState(() => _messages.addAll(rows.map((r) => _Msg(r.id, r.role, r.content))));
      _scrollToEnd();
    } catch (_) {
      // Riwayat gagal dimuat bukan blocker.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send(String text) async {
    final content = text.trim();
    if (content.isEmpty || _sending) return;
    final now = DateTime.now().microsecondsSinceEpoch;
    final user = _Msg('u-$now', 'user', content);
    final pending = _Msg('p-$now', 'assistant', '', pending: true);
    final history = [..._messages.where((m) => !m.pending && !m.error), user];
    setState(() {
      _messages.addAll([user, pending]);
      _sending = true;
    });
    _input.clear();
    _scrollToEnd();
    try {
      final turns = history
          .skip(history.length > _contextMessages ? history.length - _contextMessages : 0)
          .map((m) => ChatTurn(m.role, m.content))
          .toList();
      pending.content = await context.read<CoffeeApi>().sendChat(turns, channel: 'web');
    } catch (e) {
      pending
        ..content = errorText(e)
        ..error = true;
    } finally {
      pending.pending = false;
      if (mounted) setState(() => _sending = false);
      _scrollToEnd();
      _focus.requestFocus();
    }
  }

  Future<void> _clear() async {
    final userId = context.read<AdminSession>().profile?.id;
    if (userId == null) return;
    final repo = context.read<CoffeeRepository>();
    if (!await confirmDialog(context, 'Hapus riwayat', 'Hapus seluruh riwayat chat Anda?')) return;
    try {
      await repo.clearChatHistory(userId);
      if (mounted) setState(_messages.clear);
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 16, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Asisten AI “Kopi”', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const Text('Tanya stok, omset, menu terlaris, pengeluaran, atau prediksi — dijawab dari data real.',
              style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
                    child: Row(children: [
                      const Icon(Icons.smart_toy_outlined, size: 18, color: AppColors.coffee700),
                      const SizedBox(width: 8),
                      const Expanded(child: Text('Kopi', style: TextStyle(fontWeight: FontWeight.w700))),
                      TextButton.icon(
                        onPressed: _messages.isEmpty ? null : _clear,
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Hapus riwayat'),
                      ),
                    ]),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _messages.isEmpty
                            ? const SingleChildScrollView(
                                padding: EdgeInsets.all(24),
                                child: Column(children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: AppColors.coffee100,
                                    child: Icon(Icons.smart_toy_outlined, color: AppColors.coffee700),
                                  ),
                                  SizedBox(height: 12),
                                  Text('Halo! Saya Kopi ☕', style: TextStyle(fontWeight: FontWeight.w700)),
                                  Text('Saya menjawab berdasarkan data toko secara langsung. Coba tanyakan:',
                                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                                ]),
                              )
                            : ListView.separated(
                                controller: _scroll,
                                padding: const EdgeInsets.all(20),
                                itemCount: _messages.length,
                                separatorBuilder: (_, _) => const SizedBox(height: 12),
                                itemBuilder: (_, i) => _Bubble(msg: _messages[i]),
                              ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SizedBox(
                        height: 36,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _suggestions.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (_, i) => ActionChip(
                            label: Text(_suggestions[i], style: const TextStyle(fontSize: 12)),
                            onPressed: _sending ? null : () => _send(_suggestions[i]),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Expanded(
                          child: CallbackShortcuts(
                            bindings: {const SingleActivator(LogicalKeyboardKey.enter): () => _send(_input.text)},
                            child: TextField(
                              controller: _input,
                              focusNode: _focus,
                              minLines: 1,
                              maxLines: 5,
                              maxLength: 2000,
                              decoration: const InputDecoration(
                                hintText: 'Tulis pertanyaan… (Enter untuk kirim, Shift+Enter baris baru)',
                                counterText: '',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _sending || _input.text.trim().isEmpty ? null : () => _send(_input.text),
                          child: _sending
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.send, size: 18),
                        ),
                      ]),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg});

  final _Msg msg;

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == 'user';
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 680),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: msg.error ? AppColors.dangerSoft : (isUser ? AppColors.coffee700 : const Color(0xFFF5F5F4)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: msg.pending
          ? const Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('Kopi sedang cek data…', style: TextStyle(color: AppColors.muted)),
            ])
          : SelectableText(
              msg.content,
              style: TextStyle(
                height: 1.45,
                color: msg.error ? AppColors.danger : (isUser ? Colors.white : AppColors.text),
              ),
            ),
    );
    final avatar = CircleAvatar(
      radius: 16,
      backgroundColor: isUser ? const Color(0xFFE7E5E4) : AppColors.coffee700,
      child: Icon(isUser ? Icons.person : Icons.smart_toy_outlined, size: 16, color: isUser ? AppColors.text : Colors.white),
    );
    return Row(
      mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: isUser
          ? [Flexible(child: bubble), const SizedBox(width: 10), avatar]
          : [avatar, const SizedBox(width: 10), Flexible(child: bubble)],
    );
  }
}
