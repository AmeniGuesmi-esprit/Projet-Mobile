/// French labels for the CoachProche screens (local time).
///
/// Day / month names are written by hand so no async
/// `initializeDateFormatting` call is needed (same approach as FoodSave).
library;

import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/widgets/money_text.dart';

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

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// "18:05" (local time).
String coachClock(DateTime d) {
  final l = d.toLocal();
  return '${_two(l.hour)}:${_two(l.minute)}';
}

/// "Aujourd'hui", "Demain" or "Lun. 14 oct." (local time).
String coachDay(DateTime d, {DateTime? now}) {
  final l = d.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  if (_sameDay(l, n)) return "Aujourd'hui";
  if (_sameDay(l, n.add(const Duration(days: 1)))) return 'Demain';
  final wd = _weekdays[l.weekday - 1];
  return '${wd[0].toUpperCase()}${wd.substring(1)} ${l.day} '
      '${_months[l.month - 1]}';
}

/// "Demain · 18:30".
String coachWhen(DateTime d, {DateTime? now}) =>
    '${coachDay(d, now: now)} · ${coachClock(d)}';

/// "18:30 – 19:30".
String coachRange(DateTime start, int minutes) =>
    '${coachClock(start)} – ${coachClock(start.add(Duration(minutes: minutes)))}';

/// "45 min", "1 h", "1 h 30".
String coachDuration(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h' : '$h h ${_two(m)}';
}

/// "Gratuit" or "15,00 DT".
String coachPrice(int cents) => cents == 0 ? 'Gratuit' : MoneyText.format(cents);

/// "850 m" or "3,2 km".
String coachDistance(double km) => km < 1
    ? '${(km * 1000).round()} m'
    : '${km.toStringAsFixed(1).replaceAll('.', ',')} km';

/// "Il reste 3 places", "Complet".
String coachPlaces(CoachSessionDto s) => s.isFull
    ? 'Complet'
    : s.placesRestantes == 1
        ? '1 place restante'
        : '${s.placesRestantes} places restantes';

/// "12,5 km" style distance covered (steps-based estimate).
String coachKm(double km) => '${km.toStringAsFixed(2).replaceAll('.', ',')} km';

IconData coachTypeIcon(CoachSessionType type) => switch (type) {
      CoachSessionType.yoga => Icons.self_improvement,
      CoachSessionType.running => Icons.directions_run,
      CoachSessionType.musculation => Icons.fitness_center,
      CoachSessionType.fitness => Icons.sports_gymnastics,
      CoachSessionType.danse => Icons.music_note,
      CoachSessionType.boxe => Icons.sports_mma,
    };

/// "15,5" / "15" -> 1550 / 1500 cents; `null` when it is not an amount.
int? parseDinarsToCents(String input) {
  final cleaned = input.trim().replaceAll(',', '.');
  final value = double.tryParse(cleaned);
  if (value == null || value < 0) return null;
  return (value * 100).round();
}
