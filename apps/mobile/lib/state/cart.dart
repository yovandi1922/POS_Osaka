// apps/mobile/lib/state/cart.dart
// Keranjang belanja kasir.
import 'package:coffee_core/coffee_core.dart';
import 'package:flutter/foundation.dart';

class Cart extends ChangeNotifier {
  final List<CartLine> _lines = [];

  List<CartLine> get lines => List.unmodifiable(_lines);
  bool get isEmpty => _lines.isEmpty;
  int get count => _lines.fold(0, (s, l) => s + l.qty);
  double get total => _lines.fold(0, (s, l) => s + l.subtotal);

  int qtyOf(String menuItemId) =>
      _lines.where((l) => l.menuItemId == menuItemId).fold(0, (s, l) => s + l.qty);

  void add(MenuItem menu) {
    final i = _lines.indexWhere((l) => l.menuItemId == menu.id);
    if (i >= 0) {
      _lines[i] = _lines[i].copyWith(qty: _lines[i].qty + 1);
    } else {
      _lines.add(CartLine(menuItemId: menu.id, name: menu.name, price: menu.price, qty: 1));
    }
    notifyListeners();
  }

  void increment(String menuItemId) {
    final i = _lines.indexWhere((l) => l.menuItemId == menuItemId);
    if (i < 0) return;
    _lines[i] = _lines[i].copyWith(qty: _lines[i].qty + 1);
    notifyListeners();
  }

  void decrement(String menuItemId) {
    final i = _lines.indexWhere((l) => l.menuItemId == menuItemId);
    if (i < 0) return;
    final next = _lines[i].qty - 1;
    if (next <= 0) {
      _lines.removeAt(i);
    } else {
      _lines[i] = _lines[i].copyWith(qty: next);
    }
    notifyListeners();
  }

  void setNotes(String menuItemId, String notes) {
    final i = _lines.indexWhere((l) => l.menuItemId == menuItemId);
    if (i < 0) return;
    _lines[i] = _lines[i].copyWith(notes: notes);
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }
}
