// packages/coffee_core/test/core_test.dart
import 'package:coffee_core/coffee_core.dart';
import 'package:test/test.dart';

void main() {
  group('format', () {
    test('formatRupiah', () {
      expect(formatRupiah(15000), 'Rp 15.000');
      expect(formatRupiah(1250000.4), 'Rp 1.250.000');
      expect(formatRupiah(-2500), '-Rp 2.500');
      expect(formatRupiah(0), 'Rp 0');
    });

    test('formatNumber', () {
      expect(formatNumber(1234.5), '1.234,5');
      expect(formatNumber(2000), '2.000');
      expect(formatNumber(100, maxFractionDigits: 0), '100');
      expect(formatNumber(0.125, maxFractionDigits: 3), '0,125');
    });

    test('parse', () {
      expect(parseMoney('Rp 22.000'), 22000);
      expect(parseMoney(''), isNull);
      expect(parseDecimal('0,5'), 0.5);
      expect(parseDecimal('0.5'), 0.5);
      expect(parseDecimal('abc'), isNull);
      expect(parseDecimal('1.000'), 1000);
      expect(parseDecimal('1.234,5'), 1234.5);
      expect(parseDecimal('22,5'), 22.5);
      expect(parseDecimal('0.500'), 0.5);
      expect(parseDecimal('1.5'), 1.5);
      expect(parseDecimal(formatNumber(12500.25)), 12500.25);
      expect(formatRupiahPrecise(18.95), 'Rp 18,95');
      expect(formatRupiahPrecise(1200), 'Rp 1.200');
    });

    test('tanggal WIB', () {
      // 2026-10-21 18:30 UTC = 2026-10-22 01:30 WIB
      expect(jakartaDate(DateTime.utc(2026, 10, 21, 18, 30)), '2026-10-22');
      expect(addDays('2026-10-30', 3), '2026-11-02');
      expect(startOfMonth('2026-10-22'), '2026-10-01');
      expect(dayName('2026-10-22'), 'Kamis');
      expect(shortDate('2026-10-22'), '22 Okt');
      expect(formatDateTime(DateTime.utc(2026, 10, 22, 7, 5)), '22 Okt 2026, 14:05');
    });
  });

  group('predictRevenue', () {
    test('menangkap pola hari kerja vs akhir pekan', () {
      final history = <DailyRevenue>[];
      var d = '2026-09-21';
      for (var i = 0; i < 30; i++) {
        final dow = dayOfWeek(d);
        history.add(DailyRevenue(d, (dow == 0 || dow == 6) ? 1600000 : 1000000));
        d = addDays(d, 1);
      }
      final result = predictRevenue(history, daysAhead: 7);
      expect(result, isA<PredictSuccess>());
      final ok = result as PredictSuccess;
      expect(ok.predictions.length, 7);
      expect(ok.predictions.first.date, '2026-10-21');
      for (final p in ok.predictions) {
        final weekend = dayOfWeek(p.date) == 0 || dayOfWeek(p.date) == 6;
        expect(p.predicted, weekend ? 1600000 : 1000000);
        expect(p.low, (p.predicted * 0.85).round());
        expect(p.high, (p.predicted * 1.15).round());
      }
      expect(ok.meta.lowAccuracy, isFalse);
    });

    test('error informatif bila < 3 hari data', () {
      final result = predictRevenue(const [DailyRevenue('2026-10-01', 500000), DailyRevenue('2026-10-02', 0)]);
      expect(result, isA<PredictFailure>());
      expect((result as PredictFailure).error, contains('Minimal butuh 3 hari'));
    });

    test('hari kosong sebelum transaksi pertama diabaikan & low accuracy', () {
      final result = predictRevenue(const [
        DailyRevenue('2026-10-01', 0),
        DailyRevenue('2026-10-02', 500000),
        DailyRevenue('2026-10-03', 600000),
        DailyRevenue('2026-10-04', 700000),
      ], daysAhead: 3);
      final ok = result as PredictSuccess;
      expect(ok.meta.daysOfData, 3);
      expect(ok.meta.lowAccuracy, isTrue);
      expect(ok.predictions.map((p) => p.predicted), [600000, 600000, 600000]);
    });
  });

  group('recipeCost', () {
    const ing = {
      'kopi': Ingredient(id: 'kopi', name: 'Kopi', unit: 'gram', currentStock: 0, minStock: 0, costPerUnit: 250),
      'susu': Ingredient(id: 'susu', name: 'Susu', unit: 'ml', currentStock: 0, minStock: 0, costPerUnit: 22.5),
    };
    const recipes = [
      Recipe(id: '1', menuItemId: 'latte', ingredientId: 'kopi', qtyNeeded: 18),
      Recipe(id: '2', menuItemId: 'latte', ingredientId: 'susu', qtyNeeded: 150.5),
      Recipe(id: '3', menuItemId: 'espresso', ingredientId: 'kopi', qtyNeeded: 18),
    ];

    test('menjumlahkan takaran × harga/satuan, dibulatkan 2 desimal', () {
      expect(recipeCost('latte', recipes, ing), 4500 + 3386.25);
      expect(recipeCost('espresso', recipes, ing), 4500);
    });

    test('null bila menu belum punya resep', () {
      expect(recipeCost('teh', recipes, ing), isNull);
    });

    test('bahan yang sudah dihapus dihitung 0', () {
      expect(recipeCost('latte', recipes, {'kopi': ing['kopi']!}), 4500);
    });
  });

  group('models', () {
    test('numeric sebagai string atau num', () {
      final ing = Ingredient.fromJson({
        'id': 'a',
        'name': 'Susu',
        'unit': 'ml',
        'current_stock': '80.000',
        'min_stock': 100,
        'cost_per_unit': '18.00',
      });
      expect(ing.currentStock, 80);
      expect(ing.status, StockStatus.menipis);
      final tx = SaleTransaction.fromJson({
        'id': 't',
        'invoice_no': 'INV-1',
        'subtotal': 66000,
        'discount': 0,
        'total': '66000.00',
        'payment_method': 'cash',
        'paid_amount': 100000,
        'change': 34000,
        'status': 'paid',
        'created_at': '2026-10-22T07:00:00+00:00',
        'cashier': {'name': '', 'email': 'kasir@x.id'},
        'transaction_items': [
          {'id': 'i', 'qty': 2, 'price': 22000, 'subtotal': 44000, 'menu_item': {'name': 'Kopi Susu Gula Aren'}},
        ],
      });
      expect(tx.total, 66000);
      expect(tx.cashierName, 'kasir@x.id');
      expect(tx.items.single.menuName, 'Kopi Susu Gula Aren');
      expect(tx.itemCount, 2);
    });
  });
}
