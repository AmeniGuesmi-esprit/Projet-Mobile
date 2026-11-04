import 'dart:developer' as developer;

/// Raised by a [TeledocPaymentGateway] when the payment provider refuses an
/// operation. [message] is user-facing French.
class TeledocPaymentDeclined implements Exception {
  const TeledocPaymentDeclined([this.message = 'Paiement refusé']);

  final String message;

  @override
  String toString() => 'TeledocPaymentDeclined: $message';
}

/// TeleDoc's only contact point with the Payment module (owned by another
/// team member). TeleDoc never touches payment tables: it stores the returned
/// transaction id, without a foreign key (CONCEPTION.md, D11 and §7).
abstract class TeledocPaymentGateway {
  /// Charges [patientId] for the consultation request [requestId].
  /// Returns the transaction id. Throws [TeledocPaymentDeclined] on refusal.
  Future<int> charge({
    required int patientId,
    required int amountCents,
    required int requestId,
  });

  /// Refunds a transaction previously returned by [charge].
  /// Throws [TeledocPaymentDeclined] if the refund is refused.
  Future<void> refund({required int transactionId, required int patientId});
}

/// Default implementation until the Payment module exposes what TeleDoc needs
/// (CONCEPTION.md §7.5): every charge succeeds and returns `-requestId`. That
/// id is unique and deterministic, and it can never be mistaken for a real
/// SQLite id, which is always positive.
class MockTeledocPaymentGateway implements TeledocPaymentGateway {
  const MockTeledocPaymentGateway();

  @override
  Future<int> charge({
    required int patientId,
    required int amountCents,
    required int requestId,
  }) async {
    developer.log(
      'MOCK charge: patient #$patientId, $amountCents centimes, '
      'demande #$requestId',
      name: 'teledoc.payment',
    );
    return -requestId;
  }

  @override
  Future<void> refund({
    required int transactionId,
    required int patientId,
  }) async {
    developer.log(
      'MOCK refund: transaction $transactionId, patient #$patientId',
      name: 'teledoc.payment',
    );
  }
}
