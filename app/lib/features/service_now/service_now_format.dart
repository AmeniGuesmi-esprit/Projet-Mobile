import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../trips/trip_labels.dart';

/// "30/10/2026 à 08:49", in the device's time zone.
String formatServiceDate(DateTime value) {
  final local = value.toLocal();
  return '${formatTripDate(local)} à ${formatTripTime(local)}';
}

/// Reads an amount typed in dinars ("45", "45,5", "45.50") as whole
/// centimes, without going through a double. Null when it is not an amount.
int? parseDinars(String input) {
  final text = input.trim().replaceAll(',', '.');
  final match = RegExp(r'^(\d{1,7})(?:\.(\d{1,2}))?$').firstMatch(text);
  if (match == null) return null;
  final whole = int.parse(match.group(1)!);
  final decimals = (match.group(2) ?? '').padRight(2, '0');
  return whole * 100 + int.parse(decimals);
}

/// The value to pre-fill in an amount field, e.g. "45.50".
String dinarsText(int centimes) {
  final decimals = (centimes % 100).toString().padLeft(2, '0');
  return '${centimes ~/ 100}.$decimals';
}

/// "850 m", "5,3 km", "24 km".
String formatDistanceKm(double km) {
  if (km < 1) return '${(km * 100).round() * 10} m';
  return km < 10
      ? '${km.toStringAsFixed(1).replaceAll('.', ',')} km'
      : '${km.round()} km';
}

/// "7 min", "1 h 02".
String formatDuration(int seconds) {
  final minutes = (seconds / 60).ceil();
  if (minutes < 1) return '1 min';
  if (minutes < 60) return '$minutes min';
  final rest = (minutes % 60).toString().padLeft(2, '0');
  return '${minutes ~/ 60} h $rest';
}

/// "4,5/5 (12 avis)", or "Nouveau" without any rating.
String formatRating(double? average, int count) {
  if (average == null || count == 0) return 'Nouveau';
  final note = average.toStringAsFixed(1).replaceAll('.', ',');
  return '$note/5 ($count avis)';
}

IconData serviceTypeIcon(ServiceNowType type) => switch (type) {
      ServiceNowType.plomberie => Icons.plumbing_outlined,
      ServiceNowType.electricite => Icons.electrical_services_outlined,
      ServiceNowType.menage => Icons.cleaning_services_outlined,
      ServiceNowType.jardinage => Icons.yard_outlined,
      ServiceNowType.bricolage => Icons.handyman_outlined,
      ServiceNowType.climatisation => Icons.ac_unit_outlined,
      ServiceNowType.peinture => Icons.format_paint_outlined,
      ServiceNowType.autre => Icons.build_outlined,
    };
