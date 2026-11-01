import 'package:flutter_test/flutter_test.dart';
import 'package:proxilife/features/foodsave/client/booking/booking_format.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

/// Cash reservations stay `en_attente` (payment module rule) until the
/// merchant confirms the cash at pickup: their QR must still be usable.
void main() {
  final now = DateTime.utc(2026, 11, 1, 18);

  ReservationDto reservation({
    required PaymentMethodType mode,
    required TransactionStatus paiement,
  }) =>
      ReservationDto.fromJson({
        'id': 3,
        'date': now.toIso8601String(),
        'statut': 'en_attente',
        'panier_id': 1,
        'client_id': 9,
        'quantite_reservee': 1,
        'montant_centimes': 500,
        'mode_paiement': mode.apiValue,
        'statut_paiement': paiement.apiValue,
        'qr_token': 'FS1.3.x.y',
        'date_creation_qr': now.toIso8601String(),
        'date_expiration_qr':
            now.add(const Duration(minutes: 30)).toIso8601String(),
      });

  test('cash pending → QR active', () {
    final r = reservation(
        mode: PaymentMethodType.especes, paiement: TransactionStatus.enAttente);
    expect(isPaymentSettledForPickup(r), isTrue);
    expect(qrPhaseOf(r, now), QrPhase.active);
  });

  test('card pending → still awaiting payment', () {
    final r = reservation(
        mode: PaymentMethodType.carteBancaire,
        paiement: TransactionStatus.enAttente);
    expect(qrPhaseOf(r, now), QrPhase.awaitingPayment);
  });
}
