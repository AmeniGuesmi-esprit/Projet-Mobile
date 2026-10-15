/// Display helpers for TeleDoc (pure functions, unit-tested).
library;

/// `14/10/2026 09:05` from an ISO-8601 string (same format as the payment
/// screens; no locale data needed).
String teledocDate(String iso) {
  final date = DateTime.tryParse(iso);
  if (date == null) return iso;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year} '
      '${two(date.hour)}:${two(date.minute)}';
}

/// Estimated wait shown to the patient.
String teledocWaitLabel(int? minutes) {
  if (minutes == null) return '—';
  if (minutes <= 0) return 'Moins de 5 min';
  if (minutes < 60) return 'Environ $minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? 'Environ $hours h' : 'Environ $hours h $rest';
}

/// "3e" / "1er" — French ordinal for a queue position.
String teledocPositionLabel(int position) =>
    position == 1 ? '1er' : '${position}e';

/// Consultation length, e.g. `18 min`.
String teledocDuration(String startIso, String? endIso) {
  final start = DateTime.tryParse(startIso);
  final end = endIso == null ? null : DateTime.tryParse(endIso);
  if (start == null || end == null) return '—';
  final minutes = end.difference(start).inMinutes;
  return minutes < 1 ? 'Moins d\'1 min' : '$minutes min';
}

/// `850 m` / `1,2 km` (French decimal comma).
String teledocDistance(double? km) {
  if (km == null) return '—';
  if (km < 1) return '${((km * 1000) / 10).round() * 10} m';
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
}
