// apps/admin/lib/widgets/charts.dart
// Grafik fl_chart. Seri 1 (biru) = omset, seri 2 (oranye) = pengeluaran.
// Satu sumbu Y per grafik, garis 2px, grid samar, tooltip saat hover.
import 'package:coffee_core/coffee_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

const _axisStyle = TextStyle(fontSize: 11, color: AppColors.muted);

FlGridData _grid() => FlGridData(
      drawVerticalLine: false,
      getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.grid, strokeWidth: 1),
    );

double _niceMax(Iterable<double> values) {
  final max = values.fold<double>(0, (m, v) => v > m ? v : m);
  return max <= 0 ? 1 : max * 1.15;
}

/// Label tanggal di sumbu X — setiap [every] titik.
AxisTitles _dateAxis(List<String> dates, {int every = 5}) => AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 28,
        interval: 1,
        getTitlesWidget: (value, meta) {
          final i = value.round();
          if (i < 0 || i >= dates.length || value != i.toDouble()) return const SizedBox.shrink();
          if (i % every != 0 && i != dates.length - 1) return const SizedBox.shrink();
          return SideTitleWidget(meta: meta, child: Text(shortDate(dates[i]), style: _axisStyle));
        },
      ),
    );

AxisTitles _rupiahAxis() => AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 56,
        getTitlesWidget: (value, meta) {
          if (value == meta.max) return const SizedBox.shrink();
          return SideTitleWidget(meta: meta, child: Text(compactRupiah(value), style: _axisStyle));
        },
      ),
    );

const _noTitles = AxisTitles();

FlTitlesData _titles(List<String> dates, {int every = 5}) => FlTitlesData(
      bottomTitles: _dateAxis(dates, every: every),
      leftTitles: _rupiahAxis(),
      topTitles: _noTitles,
      rightTitles: _noTitles,
    );

/// Tren omset harian (satu seri).
class RevenueTrendChart extends StatelessWidget {
  const RevenueTrendChart({super.key, required this.data, this.height = 280});

  final List<RevenueByDay> data;
  final double height;

  @override
  Widget build(BuildContext context) {
    final dates = data.map((d) => d.day).toList();
    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: _niceMax(data.map((d) => d.revenue)),
          gridData: _grid(),
          borderData: FlBorderData(show: false),
          titlesData: _titles(dates, every: (dates.length / 6).ceil().clamp(1, 30)),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.text,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${shortDate(dates[s.x.round()])}\n${formatRupiah(s.y)} · ${data[s.x.round()].txCount} trx',
                    const TextStyle(color: Colors.white, fontSize: 12),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < data.length; i++) FlSpot(i.toDouble(), data[i].revenue)],
              isCurved: true,
              preventCurveOverShooting: true,
              color: AppColors.revenue,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: AppColors.revenue.withValues(alpha: 0.08)),
            ),
          ],
        ),
      ),
    );
  }
}

class RevenueExpensePoint {
  const RevenueExpensePoint(this.date, this.revenue, this.expense);
  final String date;
  final double revenue;
  final double expense;
}

/// Omset vs pengeluaran per hari — dua seri, satu sumbu Rupiah.
class RevenueExpenseChart extends StatelessWidget {
  const RevenueExpenseChart({super.key, required this.data, this.height = 300});

  final List<RevenueExpensePoint> data;
  final double height;

  @override
  Widget build(BuildContext context) {
    final dates = data.map((d) => d.date).toList();
    final rodWidth = data.length > 45 ? 3.0 : (data.length > 20 ? 5.0 : 9.0);
    return Column(
      children: [
        const Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          _Legend(color: AppColors.revenue, label: 'Omset'),
          SizedBox(width: 16),
          _Legend(color: AppColors.expense, label: 'Pengeluaran'),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: height,
          child: BarChart(
            BarChartData(
              minY: 0,
              maxY: _niceMax(data.expand((d) => [d.revenue, d.expense])),
              gridData: _grid(),
              borderData: FlBorderData(show: false),
              titlesData: _titles(dates, every: (dates.length / 6).ceil().clamp(1, 30)),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => AppColors.text,
                  getTooltipItem: (group, _, rod, rodIndex) => BarTooltipItem(
                    '${shortDate(dates[group.x])}\n${rodIndex == 0 ? 'Omset' : 'Pengeluaran'}: ${formatRupiah(rod.toY)}',
                    const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < data.length; i++)
                  BarChartGroupData(x: i, barsSpace: 2, barRods: [
                    BarChartRodData(
                      toY: data[i].revenue,
                      color: AppColors.revenue,
                      width: rodWidth,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                    BarChartRodData(
                      toY: data[i].expense,
                      color: AppColors.expense,
                      width: rodWidth,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Breakdown per kategori: bar horizontal sederhana (satu seri), label langsung.
class CategoryBars extends StatelessWidget {
  const CategoryBars({super.key, required this.rows, required this.color, required this.total});

  final List<MapEntry<String, double>> rows;
  final Color color;
  final double total;

  @override
  Widget build(BuildContext context) {
    final max = rows.fold<double>(0, (m, r) => r.value > m ? r.value : m);
    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Tooltip(
              message: '${r.key}: ${formatRupiah(r.value)}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(r.key, style: const TextStyle(fontWeight: FontWeight.w600))),
                    Text(formatRupiah(r.value), style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
                    SizedBox(
                      width: 56,
                      child: Text(
                        total > 0 ? '${formatNumber(r.value / total * 100, maxFractionDigits: 1)}%' : '—',
                        textAlign: TextAlign.right,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: max <= 0 ? 0 : r.value / max,
                      minHeight: 10,
                      color: color,
                      backgroundColor: AppColors.grid,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Aktual (abu-abu solid) + prediksi (biru putus-putus) + pita rentang 85–115%.
class PredictionChart extends StatelessWidget {
  const PredictionChart({super.key, required this.actual, required this.predictions, this.height = 300});

  final List<DailyRevenue> actual;
  final List<Prediction> predictions;
  final double height;

  @override
  Widget build(BuildContext context) {
    final dates = [...actual.map((a) => a.date), ...predictions.map((p) => p.date)];
    final offset = actual.length;
    // Garis prediksi disambung dari titik aktual terakhir agar kontinu.
    final predictedSpots = <FlSpot>[
      if (actual.isNotEmpty) FlSpot((offset - 1).toDouble(), actual.last.revenue),
      for (var i = 0; i < predictions.length; i++) FlSpot((offset + i).toDouble(), predictions[i].predicted.toDouble()),
    ];
    final lowSpots = [for (var i = 0; i < predictions.length; i++) FlSpot((offset + i).toDouble(), predictions[i].low.toDouble())];
    final highSpots = [for (var i = 0; i < predictions.length; i++) FlSpot((offset + i).toDouble(), predictions[i].high.toDouble())];

    LineChartBarData hidden(List<FlSpot> spots) => LineChartBarData(
          spots: spots,
          color: Colors.transparent,
          barWidth: 0,
          dotData: const FlDotData(show: false),
        );

    return Column(
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          const _Legend(color: AppColors.muted, label: 'Aktual'),
          const SizedBox(width: 16),
          const _Legend(color: AppColors.revenue, label: 'Prediksi', dashed: true),
          const SizedBox(width: 16),
          _Legend(color: AppColors.revenue.withValues(alpha: 0.2), label: 'Rentang 85–115%'),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: height,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: _niceMax([...actual.map((a) => a.revenue), ...predictions.map((p) => p.high.toDouble())]),
              gridData: _grid(),
              borderData: FlBorderData(show: false),
              titlesData: _titles(dates, every: 5),
              betweenBarsData: [BetweenBarsData(fromIndex: 2, toIndex: 3, color: AppColors.revenue.withValues(alpha: 0.12))],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => AppColors.text,
                  getTooltipItems: (spots) => [
                    for (final s in spots)
                      s.barIndex >= 2
                          ? null
                          : LineTooltipItem(
                              '${s.barIndex == 0 ? 'Aktual' : 'Prediksi'} ${shortDate(dates[s.x.round()])}\n${formatRupiah(s.y)}',
                              const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                  ],
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [for (var i = 0; i < actual.length; i++) FlSpot(i.toDouble(), actual[i].revenue)],
                  color: AppColors.muted,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                ),
                LineChartBarData(
                  spots: predictedSpots,
                  color: AppColors.revenue,
                  barWidth: 2,
                  dashArray: [6, 4],
                  dotData: FlDotData(
                    checkToShowDot: (spot, _) => spot.x >= offset,
                    getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                      radius: 4,
                      color: AppColors.revenue,
                      strokeWidth: 2,
                      strokeColor: Colors.white,
                    ),
                  ),
                ),
                hidden(lowSpots),
                hidden(highSpots),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.dashed = false});

  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      dashed
          ? Row(children: [
              for (var i = 0; i < 3; i++)
                Container(width: 4, height: 3, margin: const EdgeInsets.only(right: 2), color: color),
            ])
          : Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
    ]);
  }
}
