// apps/mobile/lib/state/auth_controller.dart
// Sesi Supabase + profil (role). supabase_flutter otomatis menyimpan sesi
// dan me-refresh token mengikuti lifecycle app.
import 'dart:async';

import 'package:coffee_core/coffee_core.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

class AuthController extends ChangeNotifier {
  AuthController(this._client, this._repo) {
    _session = _client.auth.currentSession;
    _sub = _client.auth.onAuthStateChange.listen((state) {
      _session = state.session;
      notifyListeners();
      unawaited(_loadProfile());
    });
    unawaited(_loadProfile().whenComplete(() {
      initializing = false;
      notifyListeners();
    }));
  }

  final sb.SupabaseClient _client;
  final CoffeeRepository _repo;
  late final StreamSubscription<sb.AuthState> _sub;

  sb.Session? _session;
  Profile? profile;
  bool initializing = true;

  sb.Session? get session => _session;
  bool get isSignedIn => _session != null;
  String? get userId => _session?.user.id;
  String? get accessToken => _client.auth.currentSession?.accessToken;
  bool get isAdmin => profile?.role.isAdmin ?? false;

  Future<void> _loadProfile() async {
    final uid = _session?.user.id;
    if (uid == null) {
      profile = null;
    } else {
      try {
        profile = await _repo.getProfile(uid);
      } catch (_) {
        profile = null;
      }
    }
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
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
