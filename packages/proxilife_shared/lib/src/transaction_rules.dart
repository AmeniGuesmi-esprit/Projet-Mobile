import 'enums.dart';

/// Canonical transaction status state machine. Both the app (for UI hints)
/// and the server (authoritative) must use this — never re-implement.
class TransactionRules {
  const TransactionRules._();

  static const Map<TransactionStatus, Set<TransactionStatus>> _allowed = {
    TransactionStatus.enAttente: {
      TransactionStatus.paye,
      TransactionStatus.echoue,
    },
    TransactionStatus.paye: {TransactionStatus.rembourse},
    TransactionStatus.echoue: <TransactionStatus>{},
    TransactionStatus.rembourse: <TransactionStatus>{},
  };

  static bool canTransition(TransactionStatus from, TransactionStatus to) =>
      _allowed[from]?.contains(to) ?? false;

  /// A pending transaction may be cancelled / deleted.
  static bool canCancel(TransactionStatus status) =>
      status == TransactionStatus.enAttente;

  /// Only a paid transaction may be refunded.
  static bool canRefund(TransactionStatus status) =>
      status == TransactionStatus.paye;

  static bool isTerminal(TransactionStatus status) =>
      status == TransactionStatus.echoue || status == TransactionStatus.rembourse;
}
