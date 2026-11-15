// packages/coffee_core/lib/src/repository.dart
// Semua akses data Supabase untuk app kasir & admin. RLS berlaku sesuai user yang login:
// kasir hanya melihat transaksinya sendiri; pengeluaran hanya terbaca admin/owner.
import 'package:supabase/supabase.dart';

import 'format.dart';
import 'models.dart';
import 'predict.dart';

/// Error yang ramah ditampilkan ke user.
class CoffeeException implements Exception {
  CoffeeException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CoffeeRepository {
  CoffeeRepository(this.client);

  final SupabaseClient client;

  Future<T> _guard<T>(String prefix, Future<T> Function() body) async {
    try {
      return await body();
    } on PostgrestException catch (e) {
      throw CoffeeException('$prefix: ${_friendly(e)}');
    } on AuthException catch (e) {
      throw CoffeeException('$prefix: ${e.message}');
    } on CoffeeException {
      rethrow;
    } catch (e) {
      throw CoffeeException('$prefix: $e');
    }
  }

  String _friendly(PostgrestException e) {
    if (e.code == '23505') return 'Data dengan nama tersebut sudah ada.';
    if (e.code == '42501' || e.message.contains('row-level security')) return 'Anda tidak memiliki akses untuk aksi ini.';
    return e.message;
  }

  List<Json> _rows(Object? data) => data is List ? data.whereType<Json>().toList() : const [];

  // ------------------------------------------------------------------ profil
  Future<Profile?> getProfile(String userId) => _guard('Gagal memuat profil', () async {
        final row = await client.from('profiles').select('id, email, name, role, created_at').eq('id', userId).maybeSingle();
        return row == null ? null : Profile.fromJson(row);
      });

  Future<List<Profile>> listProfiles() => _guard('Gagal memuat pengguna', () async {
        final rows = await client.from('profiles').select('id, email, name, role, created_at').order('created_at');
        return rows.map(Profile.fromJson).toList();
      });

  Future<void> updateRole(String userId, UserRole role) => _guard('Gagal mengubah role', () async {
        await client.from('profiles').update({'role': role.name}).eq('id', userId);
      });

  // ---------------------------------------------------------------- laporan
  Future<List<RevenueByDay>> revenueByDay(String start, String end) => _guard('Gagal memuat omset', () async {
        final data = await client.rpc<Object?>('revenue_by_day', params: {'p_start': start, 'p_end': end});
        return _rows(data).map(RevenueByDay.fromJson).toList();
      });

  Future<List<MenuPerformance>> menuPerformance(String start, String end) =>
      _guard('Gagal memuat performa menu', () async {
        final data = await client.rpc<Object?>('menu_performance', params: {'p_start': start, 'p_end': end});
        return _rows(data).map(MenuPerformance.fromJson).toList();
      });

  /// Riwayat omset [days] hari yang berakhir KEMARIN (hari ini belum selesai).
  Future<List<DailyRevenue>> predictionHistory({int days = 60}) async {
    final end = addDays(jakartaDate(), -1);
    final rows = await revenueByDay(addDays(end, -(days - 1)), end);
    return rows.map((r) => DailyRevenue(r.day, r.revenue)).toList();
  }

  // ------------------------------------------------------------- menu & stok
  Future<List<MenuCategory>> categories() => _guard('Gagal memuat kategori', () async {
        final rows = await client.from('menu_categories').select('id, name, sort_order').order('sort_order');
        return rows.map(MenuCategory.fromJson).toList();
      });

  Future<void> addCategory(String name, int sortOrder) => _guard('Gagal menambah kategori', () async {
        await client.from('menu_categories').insert({'name': name, 'sort_order': sortOrder});
      });

  Future<List<MenuItem>> menuItems({bool activeOnly = false}) => _guard('Gagal memuat menu', () async {
        var query = client.from('menu_items').select('id, category_id, name, price, cost, image_url, is_active');
        if (activeOnly) query = query.eq('is_active', true);
        final rows = await query.order('name');
        return rows.map(MenuItem.fromJson).toList();
      });

  Future<void> addMenuItem({
    required String name,
    String? categoryId,
    required double price,
    required double cost,
    String? imageUrl,
  }) =>
      _guard('Gagal menambah menu', () async {
        await client.from('menu_items').insert({
          'name': name,
          'category_id': categoryId,
          'price': price,
          'cost': cost,
          'image_url': imageUrl,
          'is_active': true,
        });
      });

  Future<void> updateMenuItem(String id, {bool? isActive, double? price, double? cost}) =>
      _guard('Gagal memperbarui menu', () async {
        await client.from('menu_items').update({
          'is_active': ?isActive,
          'price': ?price,
          'cost': ?cost,
        }).eq('id', id);
      });

  Future<List<Recipe>> recipes() => _guard('Gagal memuat resep', () async {
        final rows = await client.from('recipes').select('id, menu_item_id, ingredient_id, qty_needed');
        return rows.map(Recipe.fromJson).toList();
      });

  Future<void> upsertRecipe(String menuItemId, String ingredientId, double qty) => _guard('Gagal menyimpan resep', () async {
        await client.from('recipes').upsert(
          {'menu_item_id': menuItemId, 'ingredient_id': ingredientId, 'qty_needed': qty},
          onConflict: 'menu_item_id,ingredient_id',
        );
      });

  Future<void> deleteRecipe(String id) => _guard('Gagal menghapus resep', () async {
        await client.from('recipes').delete().eq('id', id);
      });

  Future<List<Ingredient>> ingredients() => _guard('Gagal memuat stok', () async {
        final rows = await client.from('ingredients').select('id, name, unit, current_stock, min_stock, cost_per_unit').order('name');
        return rows.map(Ingredient.fromJson).toList();
      });

  Future<void> addIngredient({
    required String name,
    required String unit,
    required double currentStock,
    required double minStock,
    required double costPerUnit,
  }) =>
      _guard('Gagal menambah bahan', () async {
        await client.from('ingredients').insert({
          'name': name,
          'unit': unit,
          'current_stock': currentStock,
          'min_stock': minStock,
          'cost_per_unit': costPerUnit,
        });
      });

  /// Ubah data master bahan. Stok TIDAK diubah di sini — pakai [adjustStock] agar tercatat di riwayat.
  Future<void> updateIngredient(
    String id, {
    required String name,
    required String unit,
    required double minStock,
    required double costPerUnit,
  }) =>
      _guard('Gagal memperbarui bahan', () async {
        final updated = await client
            .from('ingredients')
            .update({'name': name, 'unit': unit, 'min_stock': minStock, 'cost_per_unit': costPerUnit})
            .eq('id', id)
            .select('id');
        if (updated.isEmpty) throw CoffeeException('Anda tidak memiliki akses untuk aksi ini.');
      });

  /// Hapus bahan beserta baris resep yang memakainya (FK recipes → ingredients bersifat RESTRICT).
  /// Riwayat stock_movements bahan ini ikut terhapus (ON DELETE CASCADE).
  Future<void> deleteIngredient(String id) => _guard('Gagal menghapus bahan', () async {
        await client.from('recipes').delete().eq('ingredient_id', id);
        final deleted = await client.from('ingredients').delete().eq('id', id).select('id');
        if (deleted.isEmpty) throw CoffeeException('Anda tidak memiliki akses untuk aksi ini.');
      });

  /// Samakan menu_items.cost dengan HPP hasil resep. Menu tanpa resep dibiarkan.
  /// Mengembalikan jumlah menu yang HPP-nya diperbarui.
  Future<int> syncMenuCosts(List<MenuItem> items, List<Recipe> recipes, List<Ingredient> ingredients) =>
      _guard('Gagal menghitung HPP', () async {
        final byId = {for (final i in ingredients) i.id: i};
        var updated = 0;
        for (final item in items) {
          final cost = recipeCost(item.id, recipes, byId);
          if (cost == null || (cost - item.cost).abs() < 0.005) continue;
          await client.from('menu_items').update({'cost': cost}).eq('id', item.id);
          updated++;
        }
        return updated;
      });

  /// Stok masuk ('in') atau terbuang ('waste') via RPC adjust_stock — selalu tercatat di stock_movements.
  Future<Ingredient> adjustStock(String ingredientId, String type, double qty, {String? notes}) =>
      _guard('Gagal menyesuaikan stok', () async {
        final data = await client.rpc<Object?>('adjust_stock', params: {
          'p_ingredient_id': ingredientId,
          'p_type': type,
          'p_qty': qty,
          'p_notes': notes,
        });
        if (data is! Json) throw CoffeeException('Respons adjust_stock tidak valid');
        return Ingredient.fromJson(data);
      });

  Future<List<StockMovement>> stockMovements({int limit = 30}) => _guard('Gagal memuat riwayat stok', () async {
        final rows = await client
            .from('stock_movements')
            .select('id, type, qty, notes, created_at, ingredient:ingredients ( name, unit )')
            .order('created_at', ascending: false)
            .limit(limit);
        return rows.map(StockMovement.fromJson).toList();
      });

  // -------------------------------------------------------------- transaksi
  /// Checkout atomik via RPC create_transaction: insert transaksi + item,
  /// potong stok sesuai recipes, catat stock_movements. Harga diambil dari database.
  Future<SaleTransaction> createTransaction({
    required List<CartLine> items,
    required PaymentMethod method,
    double? paidAmount,
    double discount = 0,
  }) =>
      _guard('Transaksi gagal', () async {
        final data = await client.rpc<Object?>('create_transaction', params: {
          'p_items': items.map((i) => i.toRpcJson()).toList(),
          'p_payment_method': method.name,
          'p_paid_amount': method == PaymentMethod.cash ? paidAmount : null,
          'p_discount': discount,
        });
        if (data is! Json) throw CoffeeException('Respons create_transaction tidak valid');
        return SaleTransaction.fromJson(data);
      });

  /// [from]/[to] = tanggal WIB "YYYY-MM-DD" (inklusif). RLS: kasir hanya melihat transaksinya sendiri.
  Future<List<SaleTransaction>> recentTransactions({int limit = 100, String? from, String? to}) =>
      _guard('Gagal memuat transaksi', () async {
        var query = client.from('transactions').select(
            'id, invoice_no, cashier_id, subtotal, discount, total, payment_method, paid_amount, change, status, created_at, '
            'cashier:profiles!transactions_cashier_id_fkey ( name, email ), '
            'transaction_items ( id, qty, price, subtotal, notes, menu_item:menu_items ( name ) )');
        if (from != null) query = query.gte('created_at', '${from}T00:00:00+07:00');
        if (to != null) query = query.lt('created_at', '${addDays(to, 1)}T00:00:00+07:00');
        final rows = await query.order('created_at', ascending: false).limit(limit);
        return rows.map(SaleTransaction.fromJson).toList();
      });

  // ------------------------------------------------------------ pengeluaran
  /// Insert tanpa select: kasir boleh insert tapi tidak boleh membaca tabel expenses (RLS).
  Future<void> addExpense({
    required String userId,
    required String category,
    required double amount,
    String? description,
    String? expenseDate,
  }) =>
      _guard('Gagal menyimpan pengeluaran', () async {
        await client.from('expenses').insert({
          'category': category,
          'amount': amount,
          'description': (description == null || description.trim().isEmpty) ? null : description.trim(),
          'expense_date': expenseDate ?? jakartaDate(),
          'created_by': userId,
        });
      });

  Future<List<Expense>> recentExpenses({int limit = 100}) => _guard('Gagal memuat pengeluaran', () async {
        final rows = await client
            .from('expenses')
            .select('id, category, amount, description, expense_date, created_at, creator:profiles!expenses_created_by_fkey ( name, email )')
            .order('expense_date', ascending: false)
            .order('created_at', ascending: false)
            .limit(limit);
        return rows.map(Expense.fromJson).toList();
      });

  Future<List<Expense>> expensesInRange(String start, String end) => _guard('Gagal memuat pengeluaran', () async {
        final rows = await client
            .from('expenses')
            .select('id, category, amount, description, expense_date')
            .gte('expense_date', start)
            .lte('expense_date', end);
        return rows.map(Expense.fromJson).toList();
      });

  Future<void> deleteExpense(String id) => _guard('Gagal menghapus pengeluaran', () async {
        await client.from('expenses').delete().eq('id', id);
      });

  // ------------------------------------------------------------------- chat
  Future<List<ChatMessage>> chatHistory({int limit = 50}) => _guard('Gagal memuat riwayat chat', () async {
        final rows = await client
            .from('chat_messages')
            .select('id, role, content, created_at')
            .order('created_at', ascending: false)
            .limit(limit);
        return rows.map(ChatMessage.fromJson).toList().reversed.toList();
      });

  Future<void> clearChatHistory(String userId) => _guard('Gagal menghapus riwayat', () async {
        await client.from('chat_messages').delete().eq('user_id', userId);
      });
}
