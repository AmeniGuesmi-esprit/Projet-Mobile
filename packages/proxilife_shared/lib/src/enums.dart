/// Enumerations shared by the app and the server.
///
/// Each enum exposes [apiValue], the snake_case string stored in the
/// database and exchanged over HTTP, plus a [parse] factory that converts
/// it back (throwing [ArgumentError] on unknown values).
library;

enum UserRole {
  client('client'),
  conducteur('conducteur'),
  commercant('commercant'),
  medecin('medecin'),
  coach('coach'),
  admin('admin');

  const UserRole(this.apiValue);
  final String apiValue;

  static UserRole parse(String value) =>
      values.firstWhere((e) => e.apiValue == value,
          orElse: () => throw ArgumentError('Rôle inconnu : $value'));

  /// RIB is mandatory for professionals who receive payouts.
  bool get requiresRib => switch (this) {
        UserRole.conducteur ||
        UserRole.commercant ||
        UserRole.medecin ||
        UserRole.coach =>
          true,
        UserRole.client || UserRole.admin => false,
      };

  /// A professional can receive money from payments.
  bool get canReceivePayments => requiresRib;
}

enum AccountStatus {
  enAttenteVerification('en_attente_verification'),
  actif('actif'),
  suspendu('suspendu');

  const AccountStatus(this.apiValue);
  final String apiValue;

  static AccountStatus parse(String value) =>
      values.firstWhere((e) => e.apiValue == value,
          orElse: () => throw ArgumentError('Statut de compte inconnu : $value'));
}

enum TransactionStatus {
  enAttente('en_attente'),
  paye('paye'),
  echoue('echoue'),
  rembourse('rembourse');

  const TransactionStatus(this.apiValue);
  final String apiValue;

  static TransactionStatus parse(String value) =>
      values.firstWhere((e) => e.apiValue == value,
          orElse: () =>
              throw ArgumentError('Statut de transaction inconnu : $value'));
}

enum ServiceType {
  ecoRoute('EcoRoute'),
  foodSave('FoodSave'),
  teleDoc('TeleDoc'),
  coachProche('CoachProche'),
  serviceNow('ServiceNow');

  const ServiceType(this.apiValue);
  final String apiValue;

  static ServiceType parse(String value) =>
      values.firstWhere((e) => e.apiValue == value,
          orElse: () => throw ArgumentError('Service inconnu : $value'));
}

enum PaymentMethodType {
  carteBancaire('carte_bancaire'),
  portefeuille('portefeuille'),
  especes('especes');

  const PaymentMethodType(this.apiValue);
  final String apiValue;

  static PaymentMethodType parse(String value) =>
      values.firstWhere((e) => e.apiValue == value,
          orElse: () =>
              throw ArgumentError('Type de moyen de paiement inconnu : $value'));

  bool get isSimulatedInstant =>
      this == PaymentMethodType.carteBancaire || this == PaymentMethodType.especes;
}

enum VerificationMethod {
  email('email'),
  sms('sms');

  const VerificationMethod(this.apiValue);
  final String apiValue;

  static VerificationMethod parse(String value) =>
      values.firstWhere((e) => e.apiValue == value,
          orElse: () =>
              throw ArgumentError('Méthode de vérification inconnue : $value'));
}

enum VerificationCodeStatus {
  enAttente('en_attente'),
  valide('valide'),
  expire('expire');

  const VerificationCodeStatus(this.apiValue);
  final String apiValue;

  static VerificationCodeStatus parse(String value) =>
      values.firstWhere((e) => e.apiValue == value,
          orElse: () =>
              throw ArgumentError('Statut de code inconnu : $value'));
}
