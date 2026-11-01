import 'package:flutter/widgets.dart';

/// French date helpers for the merchant charts.
///
/// Stats days are UTC calendar days sent as `YYYY-MM-DD`; they are shown as
/// such (no local conversion: a day bucket has no time of day). Names are
/// hard-coded French so the charts never depend on async locale loading.
class ChartFormat {
  const ChartFormat._();

  static const List<String> _weekdayShort = [
    'lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'
  ];
  static const List<String> _weekdayLong = [
    'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'
  ];
  static const List<String> _monthShort = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
  ];

  /// Parses a `YYYY-MM-DD` day key (UTC). Returns null when malformed.
  static DateTime? parseDay(String day) {
    final parts = day.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime.utc(y, m, d);
  }

  /// `YYYY-MM-DD` key of [moment]'s UTC day.
  static String dayKey(DateTime moment) {
    final u = moment.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${u.year}-${two(u.month)}-${two(u.day)}';
  }

  /// "lun.", "mar."…
  static String weekdayShort(String day) {
    final d = parseDay(day);
    return d == null ? day : _weekdayShort[d.weekday - 1];
  }

  /// "lundi", "mardi"…
  static String weekdayLong(String day) {
    final d = parseDay(day);
    return d == null ? day : _weekdayLong[d.weekday - 1];
  }

  /// "lundi 12 oct."
  static String dayLabel(String day) {
    final d = parseDay(day);
    if (d == null) return day;
    return '${_weekdayLong[d.weekday - 1]} ${d.day} ${_monthShort[d.month - 1]}';
  }

  /// Compact dinar amount for bar labels: "8", "12,5", "1,2 k".
  static String compactDinars(int cents) {
    final dinars = cents / 100;
    if (dinars >= 1000) {
      return '${(dinars / 1000).toStringAsFixed(1).replaceAll('.', ',')} k';
    }
    if (dinars >= 100 || dinars == dinars.roundToDouble()) {
      return dinars.round().toString();
    }
    return dinars.toStringAsFixed(1).replaceAll('.', ',');
  }

  /// "71 %" with a French narrow no-break space before the sign.
  static String percent(num value) => '${value.round()} %';

  /// Text scaler for painted labels: follows the user setting, capped so
  /// labels stay inside the chart.
  static TextScaler chartTextScaler(BuildContext context) =>
      MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.4);
}
