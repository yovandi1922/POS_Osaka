// packages/coffee_core/lib/src/format.dart
// Format uang & tanggal. Tanggal bisnis memakai WIB (Asia/Jakarta, UTC+7, tanpa DST),
// identik dengan fungsi SQL (revenue_by_day / menu_performance) dan apps/api/lib/format.ts.

const Duration _jktOffset = Duration(hours: 7);

String _groupThousands(String digits) =>
    digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');

/// 15000 → "Rp 15.000" ; -2500 → "-Rp 2.500"
String formatRupiah(num? value) {
  final n = (value ?? 0).round();
  final sign = n < 0 ? '-' : '';
  return '${sign}Rp ${_groupThousands(n.abs().toString())}';
}

/// 1234.5 → "1.234,5" ; 2000 → "2.000"
String formatNumber(num? value, {int maxFractionDigits = 2}) {
  final raw = (value ?? 0).toStringAsFixed(maxFractionDigits);
  final fixed = raw.contains('.') ? raw.replaceFirst(RegExp(r'\.?0+$'), '') : raw;
  final parts = fixed.split('.');
  final negative = parts[0].startsWith('-');
  final intDigits = negative ? parts[0].substring(1) : parts[0];
  final intPart = '${negative ? '-' : ''}${_groupThousands(intDigits)}';
  return parts.length > 1 ? '$intPart,${parts[1]}' : intPart;
}

/// "Rp 22.000" / "22000" → 22000 ; kosong → null
double? parseMoney(String value) {
  final digits = value.replaceAll(RegExp(r'[^\d]'), '');
  return digits.isEmpty ? null : double.parse(digits);
}

/// Format Indonesia & umum: "0,5" / "0.5" → 0.5 ; "1.000" / "1.234,5" → 1000 / 1234.5 ; kosong/invalid → null.
/// Titik dianggap pemisah ribuan bila diikuti kelompok 3 digit dan tidak diawali 0 (sesuai [formatNumber]).
double? parseDecimal(String value) {
  var s = value.trim().replaceAll(RegExp(r'\s'), '');
  if (s.isEmpty) return null;
  if (s.contains(',')) {
    s = s.replaceAll('.', '').replaceFirst(',', '.');
  } else if (RegExp(r'^-?[1-9]\d{0,2}(\.\d{3})+$').hasMatch(s)) {
    s = s.replaceAll('.', '');
  }
  return double.tryParse(s);
}

/// 18.95 → "Rp 18,95" ; 1200 → "Rp 1.200" (untuk harga per satuan yang bisa berdesimal)
String formatRupiahPrecise(num? value) {
  final v = value ?? 0;
  return '${v < 0 ? '-' : ''}Rp ${formatNumber(v.abs(), maxFractionDigits: 2)}';
}

/// Tanggal lokal WIB "YYYY-MM-DD"
String jakartaDate([DateTime? at]) {
  final local = (at ?? DateTime.now()).toUtc().add(_jktOffset);
  return _ymd(local);
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _parseYmd(String date) => DateTime.parse('${date}T00:00:00Z');

/// Tambah n hari pada "YYYY-MM-DD"
String addDays(String date, int n) => _ymd(_parseYmd(date).add(Duration(days: n)));

/// "YYYY-MM-01"
String startOfMonth(String date) => '${date.substring(0, 8)}01';

/// Indeks hari 0=Minggu .. 6=Sabtu (sama dengan JS getUTCDay)
int dayOfWeek(String date) => _parseYmd(date).weekday % 7;

const List<String> dayNames = ['Minggu', 'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu'];
const List<String> _monthShort = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

String dayName(String date) => dayNames[dayOfWeek(date)];

/// "2026-10-22" → "22 Okt"
String shortDate(String date) {
  final d = _parseYmd(date);
  return '${d.day} ${_monthShort[d.month - 1]}';
}

/// "2026-10-22" → "22 Okt 2026"
String longDate(String date) => '${shortDate(date)} ${date.substring(0, 4)}';

/// Timestamp → "22 Okt 2026, 14:05" (WIB)
String formatDateTime(DateTime at) {
  final local = at.toUtc().add(_jktOffset);
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${longDate(_ymd(local))}, $hh:$mm';
}

/// Timestamp → "14:05" (WIB)
String formatTime(DateTime at) {
  final local = at.toUtc().add(_jktOffset);
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

const Map<String, String> paymentLabel = {'cash': 'Tunai', 'qris': 'QRIS', 'debit': 'Debit'};
const Map<String, String> roleLabel = {'kasir': 'Kasir', 'admin': 'Admin', 'owner': 'Owner'};

/// "1,3 jt" / "45 rb" untuk label sumbu grafik
String compactRupiah(num value) {
  final abs = value.abs();
  if (abs >= 1e9) return '${(value / 1e9).toStringAsFixed(1).replaceAll('.', ',')} M';
  if (abs >= 1e6) return '${(value / 1e6).toStringAsFixed(1).replaceAll('.', ',')} jt';
  if (abs >= 1e3) return '${(value / 1e3).round()} rb';
  return value.round().toString();
}
