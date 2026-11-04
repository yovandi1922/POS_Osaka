// packages/coffee_core/lib/src/predict.dart
// Prediksi omset harian — algoritma IDENTIK dengan apps/api/lib/predict.ts (dipakai tool AI):
//   1. Faktor day-of-week = rata-rata omset per hari (Min..Sab) / rata-rata keseluruhan
//   2. Basis = weighted moving average 7 hari terakhir (bobot linear 1..N, terbaru terberat)
//      atas omset yang sudah dinormalisasi faktor hari (hari ramai tidak terhitung dua kali)
//   3. Prediksi hari H = basis × faktor(hari H); rentang 85% .. 115%
import 'format.dart';

class DailyRevenue {
  const DailyRevenue(this.date, this.revenue);

  /// "YYYY-MM-DD" (WIB)
  final String date;
  final double revenue;
}

class Prediction {
  const Prediction({required this.date, required this.predicted, required this.low, required this.high});

  final String date;
  final int predicted;
  final int low;
  final int high;
}

class PredictionMeta {
  const PredictionMeta({
    required this.daysOfData,
    required this.windowDays,
    required this.baseDaily,
    required this.averageDaily,
    required this.dowFactors,
    required this.lowAccuracy,
  });

  final int daysOfData;
  final int windowDays;
  final int baseDaily;
  final int averageDaily;

  /// Nama hari (Minggu..Sabtu) → faktor, dibulatkan 2 desimal
  final Map<String, double> dowFactors;
  final bool lowAccuracy;

  static const String method = 'Weighted moving average 7 hari (bobot linear) × faktor hari dalam seminggu';
}

sealed class PredictResult {
  const PredictResult();
}

class PredictSuccess extends PredictResult {
  const PredictSuccess(this.predictions, this.meta);

  final List<Prediction> predictions;
  final PredictionMeta meta;

  int get total => predictions.fold(0, (s, p) => s + p.predicted);
}

class PredictFailure extends PredictResult {
  const PredictFailure(this.error, this.daysOfData);

  final String error;
  final int daysOfData;
}

const int _wmaWindow = 7;
const int _minDays = 3;
const int _lowAccuracyDays = 7;

PredictResult predictRevenue(List<DailyRevenue> history, {int daysAhead = 7}) {
  final horizon = daysAhead.clamp(1, 60);

  // Urutkan, buang duplikat tanggal (ambil yang terakhir), sanitasi angka.
  final byDate = <String, double>{};
  for (final row in history) {
    byDate[row.date] = row.revenue.isFinite && row.revenue > 0 ? row.revenue : 0;
  }
  final series = byDate.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

  // Abaikan hari kosong sebelum transaksi pertama.
  final firstActive = series.indexWhere((e) => e.value > 0);
  final data = firstActive == -1 ? <MapEntry<String, double>>[] : series.sublist(firstActive);
  final daysOfData = data.length;

  if (daysOfData < _minDays) {
    return PredictFailure(
      daysOfData == 0
          ? 'Belum ada data penjualan sama sekali, jadi prediksi belum bisa dibuat.'
          : 'Data penjualan baru $daysOfData hari. Minimal butuh $_minDays hari data untuk membuat prediksi.',
      daysOfData,
    );
  }

  // 1) Faktor day-of-week
  final overallAvg = data.fold<double>(0, (s, e) => s + e.value) / daysOfData;
  final sums = List<double>.filled(7, 0);
  final counts = List<int>.filled(7, 0);
  for (final e in data) {
    final dow = dayOfWeek(e.key);
    sums[dow] += e.value;
    counts[dow] += 1;
  }
  final factors = List<double>.generate(7, (i) {
    if (counts[i] == 0 || overallAvg <= 0) return 1; // belum ada sampel → netral
    return sums[i] / counts[i] / overallAvg;
  });

  // 2) WMA atas omset ter-normalisasi
  final window = data.length > _wmaWindow ? data.sublist(data.length - _wmaWindow) : data;
  var weightedSum = 0.0;
  var weightTotal = 0;
  for (var idx = 0; idx < window.length; idx++) {
    final weight = idx + 1;
    final factor = factors[dayOfWeek(window[idx].key)];
    final normalized = factor > 0 ? window[idx].value / factor : window[idx].value;
    weightedSum += normalized * weight;
    weightTotal += weight;
  }
  final base = weightTotal > 0 ? weightedSum / weightTotal : 0.0;

  // 3) Proyeksi mulai hari setelah data terakhir
  final lastDate = data.last.key;
  final predictions = <Prediction>[];
  for (var i = 1; i <= horizon; i++) {
    final date = addDays(lastDate, i);
    final raw = (base * factors[dayOfWeek(date)]).round();
    final predicted = raw < 0 ? 0 : raw;
    predictions.add(Prediction(
      date: date,
      predicted: predicted,
      low: (predicted * 0.85).round(),
      high: (predicted * 1.15).round(),
    ));
  }

  return PredictSuccess(
    predictions,
    PredictionMeta(
      daysOfData: daysOfData,
      windowDays: window.length,
      baseDaily: base.round(),
      averageDaily: overallAvg.round(),
      dowFactors: {for (var i = 0; i < 7; i++) dayNames[i]: (factors[i] * 100).round() / 100},
      lowAccuracy: daysOfData < _lowAccuracyDays,
    ),
  );
}
