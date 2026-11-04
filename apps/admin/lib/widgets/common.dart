// apps/admin/lib/widgets/common.dart
// Kerangka halaman, KPI card, banner, badge, dan helper kecil.
import 'package:coffee_core/coffee_core.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Kerangka halaman: judul + subjudul + aksi + konten scrollable.
class PageScaffold extends StatelessWidget {
  const PageScaffold({super.key, required this.title, this.subtitle, this.actions = const [], required this.children});

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: MediaQuery.sizeOf(context).width >= 900 ? 32 : 16, vertical: 24),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.end,
          runSpacing: 12,
          spacing: 12,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.text)),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: const TextStyle(color: AppColors.muted)),
                ],
              ],
            ),
            if (actions.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
        const SizedBox(height: 20),
        ...children,
      ],
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, this.subtitle, this.trailing, required this.child, this.padding = const EdgeInsets.all(20)});

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Row(children: [
                Expanded(child: Text(title!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                ?trailing,
              ]),
            if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            if (title != null || subtitle != null) const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class KpiCard extends StatelessWidget {
  const KpiCard({super.key, required this.label, required this.value, this.hint, required this.icon, this.tone = AppColors.coffee700, this.toneBg = AppColors.coffee100});

  final String label;
  final String value;
  final String? hint;
  final IconData icon;
  final Color tone;
  final Color toneBg;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label.toUpperCase(),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: AppColors.muted)),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 4),
                    Text(hint!, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ],
              ),
            ),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: toneBg, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: tone, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grid responsif untuk KPI card: 1 / 2 / 4 kolom.
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.children, this.maxColumns = 4});

  final List<Widget> children;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 1000 ? maxColumns : (c.maxWidth >= 560 ? 2 : 1);
      final width = (c.maxWidth - (cols - 1) * 16) / cols;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [for (final w in children) SizedBox(width: width, child: w)],
      );
    });
  }
}

/// Dua kolom di layar lebar, bertumpuk di layar sempit.
class ResponsiveRow extends StatelessWidget {
  const ResponsiveRow({super.key, required this.children, this.flex, this.breakpoint = 1000});

  final List<Widget> children;
  final List<int>? flex;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < breakpoint) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 16), children[i]],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 16),
            Expanded(flex: flex?[i] ?? 1, child: children[i]),
          ],
        ],
      );
    });
  }
}

class NoticeBanner extends StatelessWidget {
  const NoticeBanner({super.key, required this.message, this.kind = BannerKind.error});

  final String? message;
  final BannerKind kind;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    final (fg, bg, icon) = switch (kind) {
      BannerKind.error => (AppColors.danger, AppColors.dangerSoft, Icons.error_outline),
      BannerKind.success => (AppColors.success, AppColors.successSoft, Icons.check_circle_outline),
      BannerKind.warning => (AppColors.warning, AppColors.warningSoft, Icons.warning_amber),
      BannerKind.info => (AppColors.info, AppColors.infoSoft, Icons.info_outline),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: fg, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(message!, style: TextStyle(color: fg))),
      ]),
    );
  }
}

enum BannerKind { error, success, warning, info }

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, required this.fg, required this.bg});

  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

Widget stockPill(StockStatus s) => switch (s) {
      StockStatus.habis => const Pill('Habis', fg: AppColors.danger, bg: AppColors.dangerSoft),
      StockStatus.menipis => const Pill('Menipis', fg: AppColors.warning, bg: AppColors.warningSoft),
      StockStatus.aman => const Pill('Aman', fg: AppColors.success, bg: AppColors.successSoft),
    };

/// Tabel yang bisa di-scroll horizontal di layar sempit.
class ScrollTable extends StatelessWidget {
  const ScrollTable({super.key, required this.table});

  final Widget table;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(constraints: BoxConstraints(minWidth: c.maxWidth), child: table),
      ),
    );
  }
}

class LoadingBox extends StatelessWidget {
  const LoadingBox({super.key, this.height = 160});

  final double height;

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: height, child: const Center(child: CircularProgressIndicator()));
}

String errorText(Object e) => e is CoffeeException ? e.message : e.toString();

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.danger : AppColors.success,
      behavior: SnackBarBehavior.floating,
      width: 420,
    ));
}

Future<bool> confirmDialog(BuildContext context, String title, String message, {String confirm = 'Hapus'}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(confirm)),
      ],
    ),
  );
  return ok == true;
}
