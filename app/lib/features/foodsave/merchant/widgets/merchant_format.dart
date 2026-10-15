/// Pure helpers for the merchant FoodSave screens: dinar input parsing
/// (whole cents, no doubles) and French date / countdown labels.
///
/// Dates are formatted by hand (French names) so no async
/// `initializeDateFormatting` call is needed and widget tests stay simple.
library;

final RegExp _amountPattern = RegExp(r'^(\d{1,7})(?:[.,](\d{0,2}))?$');

/// Parses a dinar amount typed by the merchant ("12,5", "12.50", "0,99")
/// into whole cents WITHOUT going through a double. Returns null when the
/// text is not a valid amount (letters, negative sign, more than two
/// decimals such as "1,234", …). Zero is returned as 0 — the business rules
/// decide whether it is acceptable.
int? parseDinarsToCents(String input) {
  final text = input.trim().replaceAll(RegExp(r'\s'), '');
  final match = _amountPattern.firstMatch(text);
  if (match == null) return null;
  final units = int.parse(match.group(1)!);
  final decimals = match.group(2) ?? '';
  final cents = decimals.isEmpty ? 0 : int.parse(decimals.padRight(2, '0'));
  return units * 100 + cents;
}

/// Cents → editable French text ("1250" → "12,50").
String centsToInput(int cents) =>
    '${cents ~/ 100},${(cents % 100).toString().padLeft(2, '0')}';

const List<String> _weekdays = [
  'lun.',
  'mar.',
  'mer.',
  'jeu.',
  'ven.',
  'sam.',
  'dim.',
];

const List<String> _months = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

String _two(int v) => v.toString().padLeft(2, '0');

/// "18:05" (local time).
String formatTimeFr(DateTime d) {
  final l = d.toLocal();
  return '${_two(l.hour)}:${_two(l.minute)}';
}

/// "lun. 14 oct." (local time).
String formatDayFr(DateTime d) {
  final l = d.toLocal();
  return '${_weekdays[l.weekday - 1]} ${l.day} ${_months[l.month - 1]}';
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// "Aujourd'hui", "Demain", "Hier" or "lun. 14 oct.".
String relativeDayFr(DateTime d, {DateTime? now}) {
  final l = d.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  if (_sameDay(l, n)) return "Aujourd'hui";
  if (_sameDay(l, n.add(const Duration(days: 1)))) return 'Demain';
  if (_sameDay(l, n.subtract(const Duration(days: 1)))) return 'Hier';
  return formatDayFr(l);
}

/// "Aujourd'hui à 18:00" / "lun. 14 oct. à 18:00".
String formatDateTimeFr(DateTime d, {DateTime? now}) =>
    '${relativeDayFr(d, now: now)} à ${formatTimeFr(d)}';

/// "Aujourd'hui · 18:00 – 20:00", or "lun. 14 oct. 22:00 → mar. 15 oct. 01:00"
/// when the window spans two days.
String formatPickupWindowFr(DateTime start, DateTime end, {DateTime? now}) {
  final s = start.toLocal();
  final e = end.toLocal();
  if (_sameDay(s, e)) {
    return '${relativeDayFr(s, now: now)} · ${formatTimeFr(s)} – ${formatTimeFr(e)}';
  }
  return '${formatDayFr(s)} ${formatTimeFr(s)} → ${formatDayFr(e)} ${formatTimeFr(e)}';
}

/// Remaining time, compact: "2 j 3 h", "1 h 05 min", "12 min", "45 s".
String formatRemainingFr(Duration d) {
  if (d.isNegative || d == Duration.zero) return '0 s';
  if (d.inDays >= 1) return '${d.inDays} j ${d.inHours % 24} h';
  if (d.inHours >= 1) return '${d.inHours} h ${_two(d.inMinutes % 60)} min';
  if (d.inMinutes >= 1) return '${d.inMinutes} min';
  return '${d.inSeconds} s';
}
