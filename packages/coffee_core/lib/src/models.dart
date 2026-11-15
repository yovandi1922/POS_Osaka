// packages/coffee_core/lib/src/models.dart
// Model baris yang mencerminkan supabase/migrations/001_init.sql.
// Kolom numeric dari PostgREST bisa datang sebagai num atau String → selalu lewat _toDouble.

typedef Json = Map<String, dynamic>;

double _toDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

int _toInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.round() ?? 0;
  return 0;
}

String? _str(Object? v) => v?.toString();

DateTime _time(Object? v) => DateTime.tryParse(v?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);

Json? _obj(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is List && v.isNotEmpty && v.first is Map<String, dynamic>) return v.first as Json;
  return null;
}

List<Json> _list(Object? v) => v is List ? v.whereType<Json>().toList() : const [];

enum UserRole {
  kasir,
  admin,
  owner;

  static UserRole parse(Object? v) =>
      UserRole.values.firstWhere((r) => r.name == v, orElse: () => UserRole.kasir);

  bool get isAdmin => this == UserRole.admin || this == UserRole.owner;
  String get label => switch (this) { UserRole.kasir => 'Kasir', UserRole.admin => 'Admin', UserRole.owner => 'Owner' };
}

enum PaymentMethod {
  cash,
  qris,
  debit;

  static PaymentMethod parse(Object? v) =>
      PaymentMethod.values.firstWhere((m) => m.name == v, orElse: () => PaymentMethod.cash);

  String get label => switch (this) { PaymentMethod.cash => 'Tunai', PaymentMethod.qris => 'QRIS', PaymentMethod.debit => 'Debit' };
}

const List<String> expenseCategories = [
  'Bahan Baku',
  'Gaji',
  'Sewa',
  'Listrik & Air',
  'Operasional',
  'Marketing',
  'Peralatan',
  'Lainnya',
];

class Profile {
  const Profile({required this.id, required this.email, this.name, required this.role, required this.createdAt});

  final String id;
  final String email;
  final String? name;
  final UserRole role;
  final DateTime createdAt;

  String get displayName => (name != null && name!.trim().isNotEmpty) ? name! : email;

  factory Profile.fromJson(Json j) => Profile(
        id: j['id'] as String,
        email: _str(j['email']) ?? '',
        name: _str(j['name']),
        role: UserRole.parse(j['role']),
        createdAt: _time(j['created_at']),
      );
}

class MenuCategory {
  const MenuCategory({required this.id, required this.name, required this.sortOrder});

  final String id;
  final String name;
  final int sortOrder;

  factory MenuCategory.fromJson(Json j) =>
      MenuCategory(id: j['id'] as String, name: _str(j['name']) ?? '', sortOrder: _toInt(j['sort_order']));
}

class MenuItem {
  const MenuItem({
    required this.id,
    this.categoryId,
    required this.name,
    required this.price,
    required this.cost,
    this.imageUrl,
    required this.isActive,
  });

  final String id;
  final String? categoryId;
  final String name;
  final double price;
  final double cost;
  final String? imageUrl;
  final bool isActive;

  factory MenuItem.fromJson(Json j) => MenuItem(
        id: j['id'] as String,
        categoryId: _str(j['category_id']),
        name: _str(j['name']) ?? '',
        price: _toDouble(j['price']),
        cost: _toDouble(j['cost']),
        imageUrl: _str(j['image_url']),
        isActive: j['is_active'] == true,
      );

  MenuItem copyWith({bool? isActive, double? price, double? cost}) => MenuItem(
        id: id,
        categoryId: categoryId,
        name: name,
        price: price ?? this.price,
        cost: cost ?? this.cost,
        imageUrl: imageUrl,
        isActive: isActive ?? this.isActive,
      );
}

enum StockStatus { aman, menipis, habis }

class Ingredient {
  const Ingredient({
    required this.id,
    required this.name,
    required this.unit,
    required this.currentStock,
    required this.minStock,
    required this.costPerUnit,
  });

  final String id;
  final String name;
  final String unit;
  final double currentStock;
  final double minStock;
  final double costPerUnit;

  bool get isLow => currentStock <= minStock;

  StockStatus get status {
    if (currentStock <= 0) return StockStatus.habis;
    if (currentStock <= minStock) return StockStatus.menipis;
    return StockStatus.aman;
  }

  factory Ingredient.fromJson(Json j) => Ingredient(
        id: j['id'] as String,
        name: _str(j['name']) ?? '',
        unit: _str(j['unit']) ?? '',
        currentStock: _toDouble(j['current_stock']),
        minStock: _toDouble(j['min_stock']),
        costPerUnit: _toDouble(j['cost_per_unit']),
      );
}

class Recipe {
  const Recipe({required this.id, required this.menuItemId, required this.ingredientId, required this.qtyNeeded});

  final String id;
  final String menuItemId;
  final String ingredientId;
  final double qtyNeeded;

  factory Recipe.fromJson(Json j) => Recipe(
        id: j['id'] as String,
        menuItemId: j['menu_item_id'] as String,
        ingredientId: j['ingredient_id'] as String,
        qtyNeeded: _toDouble(j['qty_needed']),
      );
}

/// HPP per porsi dari resep: Σ (takaran × harga/satuan bahan), dibulatkan 2 desimal.
/// Mengembalikan null bila menu belum punya resep (HPP tidak bisa dihitung).
double? recipeCost(String menuItemId, Iterable<Recipe> recipes, Map<String, Ingredient> ingredientsById) {
  var found = false;
  var total = 0.0;
  for (final r in recipes) {
    if (r.menuItemId != menuItemId) continue;
    found = true;
    total += r.qtyNeeded * (ingredientsById[r.ingredientId]?.costPerUnit ?? 0);
  }
  return found ? (total * 100).roundToDouble() / 100 : null;
}

class TransactionItem {
  const TransactionItem({
    required this.id,
    required this.qty,
    required this.price,
    required this.subtotal,
    this.notes,
    this.menuName,
  });

  final String id;
  final int qty;
  final double price;
  final double subtotal;
  final String? notes;
  final String? menuName;

  factory TransactionItem.fromJson(Json j) => TransactionItem(
        id: j['id'] as String,
        qty: _toInt(j['qty']),
        price: _toDouble(j['price']),
        subtotal: _toDouble(j['subtotal']),
        notes: _str(j['notes']),
        menuName: _str(_obj(j['menu_item'])?['name']),
      );
}

class SaleTransaction {
  const SaleTransaction({
    required this.id,
    required this.invoiceNo,
    this.cashierId,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.paymentMethod,
    required this.paidAmount,
    required this.change,
    required this.status,
    required this.createdAt,
    this.cashierName,
    this.items = const [],
  });

  final String id;
  final String invoiceNo;
  final String? cashierId;
  final double subtotal;
  final double discount;
  final double total;
  final PaymentMethod paymentMethod;
  final double paidAmount;
  final double change;
  final String status;
  final DateTime createdAt;
  final String? cashierName;
  final List<TransactionItem> items;

  bool get isPaid => status == 'paid';
  int get itemCount => items.fold(0, (s, i) => s + i.qty);

  factory SaleTransaction.fromJson(Json j) {
    final cashier = _obj(j['cashier']);
    final cashierName = _str(cashier?['name']);
    return SaleTransaction(
      id: j['id'] as String,
      invoiceNo: _str(j['invoice_no']) ?? '',
      cashierId: _str(j['cashier_id']),
      subtotal: _toDouble(j['subtotal']),
      discount: _toDouble(j['discount']),
      total: _toDouble(j['total']),
      paymentMethod: PaymentMethod.parse(j['payment_method']),
      paidAmount: _toDouble(j['paid_amount']),
      change: _toDouble(j['change']),
      status: _str(j['status']) ?? 'paid',
      createdAt: _time(j['created_at']),
      cashierName: (cashierName != null && cashierName.isNotEmpty) ? cashierName : _str(cashier?['email']),
      items: _list(j['transaction_items']).map(TransactionItem.fromJson).toList(),
    );
  }
}

enum QrisStatus {
  pending,
  processing,
  paid,
  expired,
  cancelled,
  failed;

  static QrisStatus parse(Object? v) =>
      QrisStatus.values.firstWhere((s) => s.name == v, orElse: () => QrisStatus.failed);
}

/// Pembayaran QRIS dinamis (Midtrans) dari /api/payments/qris.
class QrisPayment {
  const QrisPayment({
    required this.orderId,
    required this.status,
    required this.grossAmount,
    this.qrString,
    this.qrUrl,
    this.expiresAt,
    this.error,
    this.transaction,
    this.isProduction = false,
  });

  final String orderId;
  final QrisStatus status;
  final double grossAmount;
  final String? qrString;
  final String? qrUrl;
  final DateTime? expiresAt;
  final String? error;

  /// Terisi setelah status [QrisStatus.paid].
  final SaleTransaction? transaction;
  final bool isProduction;

  /// Masih menunggu pembayaran / sedang dicatat → lanjutkan polling.
  bool get isWaiting => status == QrisStatus.pending || status == QrisStatus.processing;

  factory QrisPayment.fromJson(Json j) {
    final tx = _obj(j['transaction']);
    final expires = _str(j['expires_at']);
    return QrisPayment(
      orderId: _str(j['order_id']) ?? '',
      status: QrisStatus.parse(j['status']),
      grossAmount: _toDouble(j['gross_amount']),
      qrString: _str(j['qr_string']),
      qrUrl: _str(j['qr_url']),
      expiresAt: expires == null ? null : DateTime.tryParse(expires),
      error: _str(j['error']),
      transaction: tx == null ? null : SaleTransaction.fromJson(tx),
      isProduction: j['is_production'] == true,
    );
  }
}

class StockMovement {
  const StockMovement({
    required this.id,
    required this.type,
    required this.qty,
    this.notes,
    required this.createdAt,
    this.ingredientName,
    this.unit,
  });

  final String id;
  final String type;
  final double qty;
  final String? notes;
  final DateTime createdAt;
  final String? ingredientName;
  final String? unit;

  factory StockMovement.fromJson(Json j) {
    final ing = _obj(j['ingredient']);
    return StockMovement(
      id: j['id'] as String,
      type: _str(j['type']) ?? 'out',
      qty: _toDouble(j['qty']),
      notes: _str(j['notes']),
      createdAt: _time(j['created_at']),
      ingredientName: _str(ing?['name']),
      unit: _str(ing?['unit']),
    );
  }
}

class Expense {
  const Expense({
    required this.id,
    required this.category,
    required this.amount,
    this.description,
    required this.expenseDate,
    this.creatorName,
  });

  final String id;
  final String category;
  final double amount;
  final String? description;

  /// "YYYY-MM-DD"
  final String expenseDate;
  final String? creatorName;

  factory Expense.fromJson(Json j) {
    final creator = _obj(j['creator']);
    final name = _str(creator?['name']);
    return Expense(
      id: _str(j['id']) ?? '',
      category: _str(j['category']) ?? '',
      amount: _toDouble(j['amount']),
      description: _str(j['description']),
      expenseDate: (_str(j['expense_date']) ?? '').split('T').first,
      creatorName: (name != null && name.isNotEmpty) ? name : _str(creator?['email']),
    );
  }
}

class ChatMessage {
  const ChatMessage({required this.id, required this.role, required this.content, required this.createdAt});

  final String id;

  /// 'user' | 'assistant'
  final String role;
  final String content;
  final DateTime createdAt;

  factory ChatMessage.fromJson(Json j) => ChatMessage(
        id: j['id'] as String,
        role: _str(j['role']) ?? 'assistant',
        content: _str(j['content']) ?? '',
        createdAt: _time(j['created_at']),
      );
}

/// Baris hasil RPC revenue_by_day(p_start, p_end)
class RevenueByDay {
  const RevenueByDay({required this.day, required this.revenue, required this.txCount});

  /// "YYYY-MM-DD"
  final String day;
  final double revenue;
  final int txCount;

  factory RevenueByDay.fromJson(Json j) => RevenueByDay(
        day: (_str(j['day']) ?? '').split('T').first,
        revenue: _toDouble(j['revenue']),
        txCount: _toInt(j['tx_count']),
      );
}

/// Baris hasil RPC menu_performance(p_start, p_end)
class MenuPerformance {
  const MenuPerformance({
    required this.menuItemId,
    required this.name,
    required this.category,
    required this.isActive,
    required this.qtySold,
    required this.revenue,
  });

  final String menuItemId;
  final String name;
  final String category;
  final bool isActive;
  final int qtySold;
  final double revenue;

  factory MenuPerformance.fromJson(Json j) => MenuPerformance(
        menuItemId: j['menu_item_id'] as String,
        name: _str(j['name']) ?? '',
        category: _str(j['category']) ?? 'Tanpa Kategori',
        isActive: j['is_active'] == true,
        qtySold: _toInt(j['qty_sold']),
        revenue: _toDouble(j['revenue']),
      );
}

/// Satu baris keranjang yang dikirim ke RPC create_transaction.
class CartLine {
  const CartLine({required this.menuItemId, required this.name, required this.price, required this.qty, this.notes});

  final String menuItemId;
  final String name;
  final double price;
  final int qty;
  final String? notes;

  double get subtotal => price * qty;

  CartLine copyWith({int? qty, String? notes}) =>
      CartLine(menuItemId: menuItemId, name: name, price: price, qty: qty ?? this.qty, notes: notes ?? this.notes);

  Json toRpcJson() => {'menu_item_id': menuItemId, 'qty': qty, 'notes': notes};
}
