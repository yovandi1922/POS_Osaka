// packages/coffee_core/lib/src/chat_api.dart
// Klien HTTP ke backend Next.js (apps/api): /api/chat (asisten "Kopi") dan /api/users (buat/ubah/hapus akun).
// Auth memakai access token Supabase sebagai Bearer.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'repository.dart';

class ChatTurn {
  const ChatTurn(this.role, this.content);

  /// 'user' | 'assistant'
  final String role;
  final String content;

  Map<String, String> toJson() => {'role': role, 'content': content};
}

class CoffeeApi {
  CoffeeApi({required this.baseUrl, required this.accessToken, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  /// Base URL backend, mis. "https://coffee-pos-api.vercel.app" (tanpa "/api").
  final String baseUrl;

  /// Mengembalikan access token Supabase saat ini (null jika belum login).
  final String? Function() accessToken;
  final http.Client _http;

  Uri _uri(String path) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$base$path');
  }

  Map<String, String> _headers() {
    final token = accessToken();
    if (token == null) throw CoffeeException('Sesi berakhir, silakan login ulang.');
    return {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'};
  }

  Future<Map<String, dynamic>> _post(String path, Object body, Duration timeout) =>
      _send('POST', path, body, timeout);

  Future<Map<String, dynamic>> _send(String method, String path, Object? body, Duration timeout) async {
    if (baseUrl.isEmpty) throw CoffeeException('API_BASE_URL belum di-set (lihat env.example.json).');
    final http.Response res;
    try {
      final uri = _uri(path);
      final headers = _headers();
      final encoded = body == null ? null : jsonEncode(body);
      final Future<http.Response> req = switch (method) {
        'GET' => _http.get(uri, headers: headers),
        'PATCH' => _http.patch(uri, headers: headers, body: encoded),
        'DELETE' => _http.delete(uri, headers: headers, body: encoded),
        _ => _http.post(uri, headers: headers, body: encoded),
      };
      res = await req.timeout(timeout);
    } on TimeoutException {
      throw CoffeeException('Server terlalu lama merespons. Coba lagi.');
    } on CoffeeException {
      rethrow;
    } catch (e) {
      throw CoffeeException('Tidak dapat terhubung ke server: $e');
    }
    Map<String, dynamic> decoded;
    try {
      final parsed = jsonDecode(res.body);
      decoded = parsed is Map<String, dynamic> ? parsed : <String, dynamic>{};
    } catch (_) {
      decoded = <String, dynamic>{};
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw CoffeeException(decoded['error']?.toString() ?? 'Server error (${res.statusCode})');
    }
    return decoded;
  }

  /// Kirim percakapan ke asisten "Kopi". [channel] 'mobile' membatasi jawaban ≤120 kata.
  Future<String> sendChat(List<ChatTurn> messages, {required String channel}) async {
    final body = await _post(
      '/api/chat',
      {'channel': channel, 'messages': messages.map((m) => m.toJson()).toList()},
      const Duration(seconds: 65),
    );
    final content = body['content'];
    if (content is! String || content.isEmpty) throw CoffeeException('Jawaban kosong dari server.');
    return content;
  }

  /// Owner membuat akun staff baru.
  Future<void> createUser({
    required String email,
    required String password,
    required String name,
    required String role,
  }) async {
    await _post(
      '/api/users',
      {'email': email, 'password': password, 'name': name, 'role': role},
      const Duration(seconds: 30),
    );
  }

  /// Owner mengubah akun. Field null tidak diubah; [password] kosong/null = password tetap.
  Future<void> updateUser(String id, {String? name, String? email, String? password, String? role}) async {
    await _send(
      'PATCH',
      '/api/users',
      {
        'id': id,
        'name': ?name,
        'email': ?email,
        if (password != null && password.isNotEmpty) 'password': password,
        'role': ?role,
      },
      const Duration(seconds: 30),
    );
  }

  // ------------------------------------------------------------ QRIS Midtrans
  String _qrisPath(String orderId) => '/api/payments/qris?order_id=${Uri.encodeQueryComponent(orderId)}';

  /// Buat QRIS dinamis untuk isi keranjang. Total dihitung server dari harga menu.
  Future<QrisPayment> createQris(List<CartLine> items) async => QrisPayment.fromJson(await _post(
        '/api/payments/qris',
        {'items': items.map((i) => i.toRpcJson()).toList()},
        const Duration(seconds: 30),
      ));

  /// Cek status. Bila sudah dibayar, server sekaligus mencatat transaksi (status paid + transaction).
  Future<QrisPayment> qrisStatus(String orderId) async =>
      QrisPayment.fromJson(await _send('GET', _qrisPath(orderId), null, const Duration(seconds: 25)));

  /// Batalkan QR. Bila ternyata sudah dibayar, hasilnya tetap paid + transaksi.
  Future<QrisPayment> cancelQris(String orderId) async =>
      QrisPayment.fromJson(await _send('DELETE', _qrisPath(orderId), null, const Duration(seconds: 25)));

  /// Owner menghapus akun staff (tidak bisa menghapus akun sendiri).
  Future<void> deleteUser(String id) async {
    await _send('DELETE', '/api/users?id=${Uri.encodeQueryComponent(id)}', null, const Duration(seconds: 30));
  }
}
