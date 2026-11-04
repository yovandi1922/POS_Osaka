// apps/mobile/test/cart_test.dart
import 'package:coffee_core/coffee_core.dart';
import 'package:coffee_pos_mobile/screens/checkout_screen.dart';
import 'package:coffee_pos_mobile/state/cart.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ksga = MenuItem(id: 'm1', name: 'Kopi Susu Gula Aren', price: 22000, cost: 8000, isActive: true);
  const croissant = MenuItem(id: 'm2', name: 'Croissant', price: 22000, cost: 10000, isActive: true);

  test('tambah, increment, decrement, total', () {
    final cart = Cart()
      ..add(ksga)
      ..add(ksga)
      ..add(croissant);
    expect(cart.count, 3);
    expect(cart.total, 66000);
    expect(cart.qtyOf('m1'), 2);

    cart.decrement('m2');
    expect(cart.lines.length, 1);
    cart.increment('m1');
    expect(cart.total, 66000);
    expect(cart.lines.single.toRpcJson(), {'menu_item_id': 'm1', 'qty': 3, 'notes': null});

    cart.clear();
    expect(cart.isEmpty, isTrue);
  });

  test('saran nominal tunai', () {
    expect(quickAmounts(66000), [66000, 70000, 80000, 100000]);
    expect(quickAmounts(50000), [50000, 60000, 100000]);
  });
}
