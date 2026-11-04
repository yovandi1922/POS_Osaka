// apps/mobile/lib/screens/chat_screen.dart
// Chat dengan asisten "Kopi" → POST {API_BASE_URL}/api/chat (Bearer token), riwayat dari chat_messages.
import 'package:coffee_core/coffee_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_controller.dart';
import '../theme.dart';
import '../widgets/common.dart';

class _UiMessage {
  _UiMessage(this.id, this.role, this.content, {this.pending = false});
  final String id;
  final String role;
  String content;
  bool pending;
  bool error = false;
}

const _suggestions = ['Omset hari ini berapa?', 'Stok apa yang menipis?', 'Menu terlaris minggu ini?', 'Prediksi omset 7 hari'];
const _contextMessages = 10;

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<_UiMessage> _messages = [];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  bool _loadingHistory = true;

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
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final rows = await context.read<CoffeeRepository>().chatHistory();
      if (!mounted) return;
      setState(() => _messages.addAll(rows.map((r) => _UiMessage(r.id, r.role, r.content))));
      _scrollToEnd();
    } catch (_) {
      // Riwayat gagal dimuat bukan blocker — chat tetap bisa dipakai.
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
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
    final user = _UiMessage('u-$now', 'user', content);
    final pending = _UiMessage('p-$now', 'assistant', '', pending: true);
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
      final reply = await context.read<CoffeeApi>().sendChat(turns, channel: 'mobile');
      pending
        ..content = reply
        ..pending = false;
    } catch (e) {
      pending
        ..content = errorText(e)
        ..pending = false
        ..error = true;
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToEnd();
    }
  }

  Future<void> _clear() async {
    final userId = context.read<AuthController>().userId;
    if (userId == null) return;
    final repo = context.read<CoffeeRepository>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus riwayat'),
        content: const Text('Hapus seluruh riwayat chat Anda?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await repo.clearChatHistory(userId);
      if (mounted) setState(_messages.clear);
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asisten Kopi'),
        actions: [IconButton(onPressed: _clear, tooltip: 'Hapus riwayat', icon: const Icon(Icons.delete_outline))],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loadingHistory
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const _EmptyChat()
                    : ListView.separated(
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _Bubble(message: _messages[i]),
                      ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                for (final s in _suggestions)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(label: Text(s), onPressed: _sending ? null : () => _send(s)),
                  ),
              ],
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: SafeArea(
              top: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      decoration: const InputDecoration(hintText: 'Tulis pertanyaan…', counterText: ''),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending || _input.text.trim().isEmpty ? null : () => _send(_input.text),
                    icon: _sending
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send),
                    tooltip: 'Kirim',
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

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(radius: 28, backgroundColor: AppColors.primarySoft, child: Icon(Icons.local_cafe, color: AppColors.primary)),
          SizedBox(height: 12),
          Text('Halo! Saya Kopi ☕', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          SizedBox(height: 4),
          Text('Tanya apa saja soal stok, penjualan, dan menu. Saya jawab dari data toko.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
        ]),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final _UiMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final bg = message.error ? AppColors.dangerSoft : (isUser ? AppColors.primary : Colors.white);
    final fg = message.error ? AppColors.danger : (isUser ? Colors.white : AppColors.text);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            border: isUser ? null : Border.all(color: AppColors.border),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
          ),
          child: message.pending
              ? const Row(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Kopi sedang cek data…', style: TextStyle(color: AppColors.muted)),
                ])
              : SelectableText(message.content, style: TextStyle(color: fg, fontSize: 15, height: 1.4)),
        ),
      ),
    );
  }
}
