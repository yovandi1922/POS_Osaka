// apps/admin/lib/theme.dart
import 'package:flutter/material.dart';

class AppColors {
  static const coffee950 = Color(0xFF2B1912);
  static const coffee700 = Color(0xFF734932);
  static const coffee600 = Color(0xFF8F5E3C);
  static const coffee100 = Color(0xFFF1E8DE);
  static const coffee200 = Color(0xFFE2CFBB);
  static const background = Color(0xFFFAFAF9);
  static const border = Color(0xFFE7E5E4);
  static const text = Color(0xFF1C1917);
  static const muted = Color(0xFF78716C);
  static const success = Color(0xFF047857);
  static const successSoft = Color(0xFFD1FAE5);
  static const warning = Color(0xFFB45309);
  static const warningSoft = Color(0xFFFEF3C7);
  static const danger = Color(0xFFB91C1C);
  static const dangerSoft = Color(0xFFFEE2E2);
  static const info = Color(0xFF1D4ED8);
  static const infoSoft = Color(0xFFDBEAFE);

  // Seri grafik: 1 = omset (biru), 2 = pengeluaran (oranye)
  static const revenue = Color(0xFF2A78D6);
  static const expense = Color(0xFFEB6834);
  static const grid = Color(0xFFE7E5E4);
}

ThemeData buildTheme() {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: Color(0xFFD6D3D1)),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.coffee700, primary: AppColors.coffee700, surface: Colors.white),
    scaffoldBackgroundColor: AppColors.background,
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(borderSide: const BorderSide(color: AppColors.coffee700, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 42),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 42),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    dataTableTheme: const DataTableThemeData(
      headingTextStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted),
      headingRowColor: WidgetStatePropertyAll(Color(0xFFFAFAF9)),
    ),
  );
}
