// apps/admin/lib/state/admin_session.dart
// Sesi Supabase + profil. Hanya role admin/owner yang boleh memakai web admin;
// akun kasir otomatis di-logout dan diberi pesan.
import 'dart:async';

import 'package:coffee_core/coffee_core.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

class AdminSession extends ChangeNotifier {
  AdminSession(this._client, this._repo) {
    _sub = _client.auth.onAuthStateChange.listen((state) => unawaited(_sync(state.session)));
    unawaited(_sync(_client.auth.currentSession));
  }

  final sb.SupabaseClient _client;
  final CoffeeRepository _repo;
  late final StreamSubscription<sb.AuthState> _sub;

  bool ready = false;
  sb.Session? session;
  Profile? profile;

  /// Pesan untuk halaman login (mis. akun kasir mencoba masuk).
  String? notice;

  bool get signedIn => session != null;
  bool get profileLoading => signedIn && profile == null;
  bool get isOwner => profile?.role == UserRole.owner;
  String? get accessToken => _client.auth.currentSession?.accessToken;

  String? _syncedUserId;

  Future<void> _sync(sb.Session? next) async {
    session = next;
    final uid = next?.user.id;
    if (uid == null) {
      profile = null;
      _syncedUserId = null;
    } else if (uid != _syncedUserId) {
      _syncedUserId = uid;
      profile = null;
      notifyListeners();
      try {
        final p = await _repo.getProfile(uid);
        if (p == null || !p.role.isAdmin) {
          notice = 'Akun ${p?.role.label.toLowerCase() ?? 'tanpa profil'} tidak memiliki akses ke web admin. '
              'Hanya role admin/owner yang diizinkan.';
          await _client.auth.signOut();
          return;
        }
        profile = p;
      } catch (e) {
        notice = 'Gagal memuat profil: $e';
        await _client.auth.signOut();
        return;
      }
    }
    ready = true;
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    notice = null;
    try {
      await _client.auth.signInWithPassword(email: email.trim(), password: password);
    } on sb.AuthException catch (e) {
      throw CoffeeException(e.message == 'Invalid login credentials' ? 'Email atau password salah.' : e.message);
    }
  }

  Future<void> signOut() => _client.auth.signOut();

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
