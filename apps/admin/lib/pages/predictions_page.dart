// apps/admin/lib/pages/predictions_page.dart
// Tabel & grafik prediksi 14 hari dari predictRevenue() (coffee_core) dengan 60 hari data historis.
import 'package:coffee_core/coffee_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

const _horizon = 14;

class PredictionsPage extends StatefulWidget {
  const PredictionsPage({super.key});

  @override
  State<PredictionsPage> createState() => _PredictionsPageState();
}

class _PredictionsPageState extends State<PredictionsPage> {
  List<DailyRevenue> _history = [];
  PredictResult? _result;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final history = await context.read<CoffeeRepository>().predictionHistory(days: 60);
      if (!mounted) return;
      setState(() {
        _history = history;
        _result = predictRevenue(history, daysAhead: _horizon);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return PageScaffold(
      title: 'Prediksi omset $_horizon hari',
      subtitle: 'Berdasarkan data 60 hari terakhir (hingga kemarin).',
      children: [
        NoticeBanner(message: _error),
        const NoticeBanner(
          kind: BannerKind.info,
          message: 'Disclaimer: prediksi ini estimasi statistik (weighted moving average 7 hari × faktor hari dalam seminggu), '
              'bukan jaminan. Hasil bisa meleset karena cuaca, event, promo, hari libur, atau perubahan menu. '
              'Rentang 85%–115% menunjukkan ketidakpastian.',
        ),
        if (_loading) const LoadingBox(),
        if (result is PredictFailure)
          SectionCard(
            child: Row(children: [
              const Icon(Icons.warning_amber, color: AppColors.warning),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Prediksi belum tersedia', style: TextStyle(fontWeight: FontWeight.w700)),
                  Text(result.error, style: const TextStyle(color: AppColors.muted)),
                ]),
              ),
            ]),
          ),
        if (result is PredictSuccess) ...[
          if (result.meta.lowAccuracy)
            NoticeBanner(
              kind: BannerKind.warning,
              message: 'Data historis baru ${result.meta.daysOfData} hari (< 7 hari), sehingga akurasi prediksi masih rendah.',
            ),
          KpiGrid(maxColumns: 3, children: [
            KpiCard(
              label: 'Total prediksi $_horizon hari',
              value: formatRupiah(result.total),
              hint: '${formatRupiah(result.total * 0.85)} – ${formatRupiah(result.total * 1.15)}',
              icon: Icons.trending_up,
            ),
            KpiCard(
              label: 'Basis harian (WMA)',
              value: formatRupiah(result.meta.baseDaily),
              hint: 'Rata-rata keseluruhan ${formatRupiah(result.meta.averageDaily)}',
              icon: Icons.functions,
            ),
            KpiCard(
              label: 'Data historis',
              value: '${result.meta.daysOfData} hari',
              hint: 'Jendela WMA ${result.meta.windowDays} hari',
              icon: Icons.history,
            ),
          ]),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Aktual 21 hari terakhir & prediksi',
            subtitle: 'Garis putus = prediksi, area = rentang 85–115%',
            child: PredictionChart(
              actual: _history.length > 21 ? _history.sublist(_history.length - 21) : _history,
              predictions: result.predictions,
            ),
          ),
          const SizedBox(height: 16),
          ResponsiveRow(flex: const [2, 1], children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: ScrollTable(
                table: DataTable(
                  columns: const [
                    DataColumn(label: Text('TANGGAL')),
                    DataColumn(label: Text('HARI')),
                    DataColumn(label: Text('PREDIKSI'), numeric: true),
                    DataColumn(label: Text('RENDAH (85%)'), numeric: true),
                    DataColumn(label: Text('TINGGI (115%)'), numeric: true),
                  ],
                  rows: [
                    for (final p in result.predictions)
                      DataRow(cells: [
                        DataCell(Text(longDate(p.date))),
                        DataCell(Text(dayName(p.date))),
                        DataCell(Text(formatRupiah(p.predicted), style: const TextStyle(fontWeight: FontWeight.w700))),
                        DataCell(Text(formatRupiah(p.low), style: const TextStyle(color: AppColors.muted))),
                        DataCell(Text(formatRupiah(p.high), style: const TextStyle(color: AppColors.muted))),
                      ]),
                  ],
                ),
              ),
            ),
            SectionCard(
              title: 'Faktor hari',
              subtitle: 'Rata-rata omset per hari ÷ rata-rata keseluruhan. > 1 = lebih ramai.',
              child: Column(children: [
                for (final e in result.meta.dowFactors.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Expanded(child: Text(e.key)),
                      Text('×${e.value.toStringAsFixed(2)}',
                          style: TextStyle(fontWeight: FontWeight.w600, color: e.value >= 1 ? AppColors.success : AppColors.muted)),
                    ]),
                  ),
              ]),
            ),
          ]),
        ],
      ],
    );
  }
}
