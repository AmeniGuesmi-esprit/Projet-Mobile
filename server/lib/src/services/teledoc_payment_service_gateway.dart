import 'dart:developer' as developer;

import 'package:proxilife_shared/proxilife_shared.dart';

import '../api_error.dart';
import 'payment_service.dart';
import 'teledoc_payment_gateway.dart';

/// Real adapter (Étape 11): TeleDoc payments go through the Payment module's
/// [PaymentService], called as is, never modified (CONCEPTION.md §7.6).
///
/// Not the default yet: [PaymentService.createTransaction] needs a
/// beneficiary that is unknown when the request is created (the doctor is
/// assigned later). Until Fawzi exposes a platform account, the adapter
/// credits a configured [beneficiaryEmail] (an active professional account
/// with a RIB, chosen with him).
class PaymentServiceTeledocGateway implements TeledocPaymentGateway {
  PaymentServiceTeledocGateway(this._payments,
      {required this.beneficiaryEmail});

  final PaymentService _payments;
  final String beneficiaryEmail;

  @override
  Future<int> charge({
    required int patientId,
    required int amountCents,
    required int requestId,
  }) async {
    final TransactionDto transaction;
    try {
      transaction = await _payments.createTransaction(
        patientId,
        montantCentimes: amountCents,
        beneficiaireEmail: beneficiaryEmail,
        typeService: ServiceType.teleDoc,
        idReference: 'TD-$requestId',
      );
    } on ApiError catch (e) {
      // e.g. « Ajoutez d'abord un moyen de paiement », expired card.
      throw TeledocPaymentDeclined(e.message);
    }
    if (transaction.statut != TransactionStatus.paye) {
      // Wallet payment with an insufficient balance (`echoue`).
      throw const TeledocPaymentDeclined(
          'Paiement refusé : solde du portefeuille insuffisant');
    }
    return transaction.id;
  }

  @override
  Future<void> refund({
    required int transactionId,
    required int patientId,
  }) async {
    if (transactionId <= 0) {
      // Paid with the mock before the switch: no real money to give back.
      developer.log('Transaction fictive $transactionId : rien à rembourser',
          name: 'teledoc.payment');
      return;
    }
    try {
      await _payments.refund(transactionId, patientId, UserRole.client);
    } on ApiError catch (e) {
      throw TeledocPaymentDeclined(e.message);
    }
  }
}

/// The gateway to wire in `buildApp`: the real adapter when a beneficiary is
/// configured, the mock otherwise. Plugging it is one line in `app.dart`,
/// to be done with Fawzi (CONCEPTION.md §7.6).
TeledocPaymentGateway teledocPaymentGateway(
  PaymentService payments, {
  String? beneficiaryEmail,
}) {
  final email = beneficiaryEmail?.trim() ?? '';
  return email.isEmpty
      ? const MockTeledocPaymentGateway()
      : PaymentServiceTeledocGateway(payments, beneficiaryEmail: email);
}
