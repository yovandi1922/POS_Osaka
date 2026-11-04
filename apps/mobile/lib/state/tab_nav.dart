// apps/mobile/lib/state/tab_nav.dart
// Tab aktif di bottom navigation; screen mendengarkan ini untuk refresh saat tab dibuka.
import 'package:flutter/foundation.dart';

enum AppTab { home, kasir, stok, pengeluaran, laporan, asisten }

class TabNav extends ChangeNotifier {
  AppTab _current = AppTab.home;

  AppTab get current => _current;

  void go(AppTab tab) {
    if (_current == tab) return;
    _current = tab;
    notifyListeners();
  }
}
