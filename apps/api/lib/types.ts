// apps/api/lib/types.ts
// Tipe baris yang mencerminkan supabase/migrations/001_init.sql.
// Kolom numeric dari PostgREST dikembalikan sebagai number; selalu dibungkus Number() saat dihitung.

export type UserRole = 'kasir' | 'admin' | 'owner';
export type PaymentMethod = 'cash' | 'qris' | 'debit';
export type TransactionStatus = 'paid' | 'void';
export type StockMovementType = 'in' | 'out' | 'waste';
export type ChatRole = 'user' | 'assistant';

export interface Profile {
  id: string;
  email: string;
  name: string | null;
  role: UserRole;
  created_at: string;
}

export interface MenuCategory {
  id: string;
  name: string;
  sort_order: number;
}

export interface MenuItem {
  id: string;
  category_id: string | null;
  name: string;
  price: number;
  cost: number;
  image_url: string | null;
  is_active: boolean;
  created_at: string;
}

export interface Ingredient {
  id: string;
  name: string;
  unit: string;
  current_stock: number;
  min_stock: number;
  cost_per_unit: number;
}

export interface Recipe {
  id: string;
  menu_item_id: string;
  ingredient_id: string;
  qty_needed: number;
}

export interface Transaction {
  id: string;
  invoice_no: string;
  cashier_id: string | null;
  subtotal: number;
  discount: number;
  total: number;
  payment_method: PaymentMethod;
  paid_amount: number;
  change: number;
  status: TransactionStatus;
  created_at: string;
}

export interface TransactionItem {
  id: string;
  transaction_id: string;
  menu_item_id: string;
  qty: number;
  price: number;
  subtotal: number;
  notes: string | null;
}

export interface StockMovement {
  id: string;
  ingredient_id: string;
  type: StockMovementType;
  qty: number;
  notes: string | null;
  ref_transaction_id: string | null;
  created_by: string | null;
  created_at: string;
}

export interface Expense {
  id: string;
  category: string;
  amount: number;
  description: string | null;
  expense_date: string;
  created_by: string | null;
  created_at: string;
}

export interface ChatMessage {
  id: string;
  user_id: string;
  role: ChatRole;
  content: string;
  tool_calls_json: unknown;
  created_at: string;
}

/** Baris hasil RPC revenue_by_day(p_start, p_end) */
export interface RevenueByDayRow {
  day: string;
  revenue: number;
  tx_count: number;
}

/** Baris hasil RPC menu_performance(p_start, p_end) */
export interface MenuPerformanceRow {
  menu_item_id: string;
  name: string;
  category: string;
  is_active: boolean;
  qty_sold: number;
  revenue: number;
}

export const EXPENSE_CATEGORIES = [
  'Bahan Baku',
  'Gaji',
  'Sewa',
  'Listrik & Air',
  'Operasional',
  'Marketing',
  'Peralatan',
  'Lainnya',
] as const;

export function isAdminRole(role: string | null | undefined): role is 'admin' | 'owner' {
  return role === 'admin' || role === 'owner';
}
