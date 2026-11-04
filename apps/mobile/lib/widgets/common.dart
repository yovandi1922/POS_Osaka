// apps/mobile/lib/widgets/common.dart
// Komponen UI kecil yang dipakai berulang.
import 'package:coffee_core/coffee_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

class KpiTile extends StatelessWidget {
  const KpiTile({super.key, required this.label, required this.value, this.hint, this.tone});

  final String label;
  final String value;
  final String? hint;

  /// null = netral
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text)),
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint!, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          ],
        ],
      ),
    );
  }
}

class MessageBanner extends StatelessWidget {
  const MessageBanner({super.key, required this.message, this.isError = true});

  final String? message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? AppColors.dangerSoft : AppColors.successSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message!,
        style: TextStyle(color: isError ? AppColors.danger : AppColors.success, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});

  final StockStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = switch (status) {
      StockStatus.habis => ('Habis', AppColors.danger, AppColors.dangerSoft),
      StockStatus.menipis => ('Menipis', AppColors.warning, AppColors.warningSoft),
      StockStatus.aman => ('Aman', AppColors.success, AppColors.successSoft),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

/// Ambil pesan error yang ramah dari exception.
String errorText(Object e) => e is CoffeeException ? e.message : e.toString();

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.danger : AppColors.success,
      behavior: SnackBarBehavior.floating,
    ));
}
