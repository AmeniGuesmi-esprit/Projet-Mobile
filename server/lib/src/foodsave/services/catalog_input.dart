import 'package:proxilife_shared/proxilife_shared.dart';

import '../../api_error.dart';

/// Strict JSON field readers for the FoodSave catalogue. Every failure is an
/// [ApiError.badRequest] with a French message naming the field.

/// French labels used in validation messages.
const Map<String, String> _labels = {
  'nom': 'nom',
  'adresse': 'adresse',
  'latitude': 'latitude',
  'longitude': 'longitude',
  'categorie': 'catégorie',
  'titre': 'titre',
  'contenu': 'contenu',
  'prix_centimes': 'prix réduit',
  'prix_initial_centimes': 'prix initial',
  'quantite': 'quantité',
  'creneau_retrait_debut': 'début du créneau de retrait',
  'creneau_retrait_fin': 'fin du créneau de retrait',
  'date_expiration': 'date d\'expiration',
};

String _label(String key) => _labels[key] ?? key;

ApiError _missing(String key) =>
    ApiError.badRequest('Champ obligatoire manquant : ${_label(key)}');

ApiError _invalid(String key) =>
    ApiError.badRequest('Valeur invalide pour le champ : ${_label(key)}');

String? optString(Map<String, dynamic> body, String key) {
  final v = body[key];
  if (v == null) return null;
  if (v is! String) throw _invalid(key);
  return v.trim();
}

String reqString(Map<String, dynamic> body, String key) =>
    optString(body, key) ?? (throw _missing(key));

/// Accepts JSON integers only (money is always whole cents). A double with
/// no fractional part (e.g. `500.0`) is tolerated.
int? optInt(Map<String, dynamic> body, String key) {
  final v = body[key];
  if (v == null) return null;
  if (v is int) return v;
  if (v is double && v.isFinite && v == v.truncateToDouble()) {
    return v.toInt();
  }
  throw _invalid(key);
}

int reqInt(Map<String, dynamic> body, String key) =>
    optInt(body, key) ?? (throw _missing(key));

double? optDouble(Map<String, dynamic> body, String key) {
  final v = body[key];
  if (v == null) return null;
  if (v is num) return v.toDouble();
  throw _invalid(key);
}

double reqDouble(Map<String, dynamic> body, String key) =>
    optDouble(body, key) ?? (throw _missing(key));

/// ISO-8601 date, returned in UTC.
DateTime? optDate(Map<String, dynamic> body, String key) {
  final v = body[key];
  if (v == null) return null;
  if (v is! String) throw _invalid(key);
  final parsed = DateTime.tryParse(v.trim());
  if (parsed == null) throw _invalid(key);
  return parsed.toUtc();
}

DateTime reqDate(Map<String, dynamic> body, String key) =>
    optDate(body, key) ?? (throw _missing(key));

FoodCategory? optCategory(Map<String, dynamic> body, String key) {
  final v = body[key];
  if (v == null) return null;
  if (v is! String) throw _invalid(key);
  return parseCategory(v);
}

FoodCategory reqCategory(Map<String, dynamic> body, String key) =>
    optCategory(body, key) ?? (throw _missing(key));

FoodCategory parseCategory(String value) {
  for (final c in FoodCategory.values) {
    if (c.apiValue == value) return c;
  }
  throw ApiError.badRequest('Catégorie inconnue : $value');
}

BasketStatus parseBasketStatus(String value) {
  for (final s in BasketStatus.values) {
    if (s.apiValue == value) return s;
  }
  throw ApiError.badRequest('Statut de panier inconnu : $value');
}

BasketSort parseBasketSort(String value) {
  for (final s in BasketSort.values) {
    if (s.apiValue == value) return s;
  }
  throw ApiError.badRequest('Tri inconnu : $value');
}

/// Canonical UTC ISO-8601 representation stored in the database.
String isoUtc(DateTime d) => d.toUtc().toIso8601String();

/// Escapes `%`, `_` and the escape char itself for `LIKE ... ESCAPE '\'`.
String escapeLike(String input) => input
    .replaceAll(r'\', r'\\')
    .replaceAll('%', r'\%')
    .replaceAll('_', r'\_');
