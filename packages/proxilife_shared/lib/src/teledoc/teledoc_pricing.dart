/// TeleDoc consultation price (whole cents, default currency TND): 30 DT.
///
/// Charged through `TeledocPaymentGateway` on the server when a request is
/// created; the client never sends an amount.
class TeledocPricing {
  const TeledocPricing._();

  static const int consultationCents = 3000;
}
