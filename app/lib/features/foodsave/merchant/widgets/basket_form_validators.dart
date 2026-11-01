/// Field-level validators of the basket form (French messages). They mirror
/// [FoodSaveRules.basketError] so errors show under the right field; the
/// global rule check (dates) still runs on submit and the server stays
/// authoritative.
library;

import 'merchant_format.dart';

/// Maximum initial price accepted by the rules (1 000 000 DT).
const int maxBasketPriceCents = 100000000;

String? validateBasketTitle(String? value) {
  final t = (value ?? '').trim();
  if (t.isEmpty) return 'Indiquez un titre (ex. « Panier du soir »)';
  if (t.length < 3 || t.length > 80) {
    return 'Le titre doit contenir entre 3 et 80 caractères';
  }
  return null;
}

String? validateBasketContent(String? value) {
  final c = (value ?? '').trim();
  if (c.isEmpty) return 'Décrivez le contenu du panier';
  if (c.length < 3 || c.length > 500) {
    return 'Le contenu doit contenir entre 3 et 500 caractères';
  }
  return null;
}

String? validateReducedPrice(String? value) {
  if ((value ?? '').trim().isEmpty) return 'Indiquez le prix réduit';
  final cents = parseDinarsToCents(value!);
  if (cents == null) return 'Montant invalide (ex. 12,50)';
  if (cents <= 0) return 'Le prix réduit doit être supérieur à 0';
  return null;
}

/// [reducedPrice] is the raw text of the reduced price field.
String? validateInitialPrice(String? value, String reducedPrice) {
  if ((value ?? '').trim().isEmpty) return 'Indiquez le prix initial';
  final cents = parseDinarsToCents(value!);
  if (cents == null) return 'Montant invalide (ex. 30,00)';
  if (cents > maxBasketPriceCents) return 'Prix initial trop élevé';
  final reduced = parseDinarsToCents(reducedPrice);
  if (reduced != null && reduced > 0 && cents <= reduced) {
    return 'Le prix initial doit être supérieur au prix réduit';
  }
  return null;
}

/// At creation at least one unit must be on sale; when editing, 0 is
/// allowed (the basket then becomes « Épuisé »).
String? validateBasketQuantity(String? value, {required bool creating}) {
  final q = int.tryParse((value ?? '').trim());
  if (q == null) return 'Quantité invalide';
  if (q < 0) return 'La quantité ne peut pas être négative';
  if (creating && q < 1) return 'La quantité doit être d\'au moins 1';
  if (q > 999) return 'Quantité trop élevée (999 maximum)';
  return null;
}
