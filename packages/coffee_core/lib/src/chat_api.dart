// packages/coffee_core/lib/src/chat_api.dart
// Klien HTTP ke backend Next.js (apps/api): /api/chat (asisten "Kopi") dan /api/users.
// Auth memakai access token Supabase sebagai Bearer.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

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

  Future<Map<String, dynamic>> _post(String path, Object body, Duration timeout) async {
    if (baseUrl.isEmpty) throw CoffeeException('API_BASE_URL belum di-set (lihat env.example.json).');
    final http.Response res;
    try {
      res = await _http.post(_uri(path), headers: _headers(), body: jsonEncode(body)).timeout(timeout);
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
}
