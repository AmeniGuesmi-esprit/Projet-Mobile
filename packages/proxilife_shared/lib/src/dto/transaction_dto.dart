import '../enums.dart';

/// Direction of a transaction relative to the requesting user.
enum TransactionDirection {
  /// Money left the user's account (they are the payer).
  debit('debit'),

  /// Money entered the user's account (they are the beneficiary).
  credit('credit');

  const TransactionDirection(this.apiValue);
  final String apiValue;

  static TransactionDirection? tryParse(String? value) {
    if (value == null) return null;
    for (final d in values) {
      if (d.apiValue == value) return d;
    }
    return null;
  }
}

/// A transaction as seen by the client. Amounts are whole cents.
class TransactionDto {
  const TransactionDto({
    required this.id,
    required this.montantCentimes,
    required this.devise,
    required this.dateIso,
    required this.statut,
    required this.typeService,
    required this.factureNumero,
    this.idReference,
    this.idMoyenPaiement,
    this.moyenPaiementType,
    this.direction,
    this.beneficiaireNom,
    this.beneficiaireEmail,
    this.payeurNom,
    this.payeurEmail,
  });

  final int id;
  final int montantCentimes;
  final String devise;
  final String dateIso;
  final TransactionStatus statut;
  final ServiceType typeService;
  final String? idReference;
  final String factureNumero;
  final int? idMoyenPaiement;

  /// Type of the payment method used (card / wallet / cash), when known.
  final PaymentMethodType? moyenPaiementType;

  /// Debit or credit from the requesting user's point of view. Null on
  /// responses that aren't tied to a user (legacy).
  final TransactionDirection? direction;
  final String? beneficiaireNom;
  final String? beneficiaireEmail;
  final String? payeurNom;
  final String? payeurEmail;

  factory TransactionDto.fromJson(Map<String, dynamic> json) => TransactionDto(
        id: json['id'] as int,
        montantCentimes: json['montant_centimes'] as int,
        devise: json['devise'] as String,
        dateIso: json['date'] as String,
        statut: TransactionStatus.parse(json['statut'] as String),
        typeService: ServiceType.parse(json['type_service'] as String),
        idReference: json['id_reference'] as String?,
        factureNumero: json['facture_numero'] as String,
        idMoyenPaiement: json['id_moyen_paiement'] as int?,
        moyenPaiementType: json['moyen_paiement_type'] == null
            ? null
            : PaymentMethodType.parse(json['moyen_paiement_type'] as String),
        direction: TransactionDirection.tryParse(json['direction'] as String?),
        beneficiaireNom: json['beneficiaire_nom'] as String?,
        beneficiaireEmail: json['beneficiaire_email'] as String?,
        payeurNom: json['payeur_nom'] as String?,
        payeurEmail: json['payeur_email'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'montant_centimes': montantCentimes,
        'devise': devise,
        'date': dateIso,
        'statut': statut.apiValue,
        'type_service': typeService.apiValue,
        'id_reference': idReference,
        'facture_numero': factureNumero,
        'id_moyen_paiement': idMoyenPaiement,
        'moyen_paiement_type': moyenPaiementType?.apiValue,
        'direction': direction?.apiValue,
        'beneficiaire_nom': beneficiaireNom,
        'beneficiaire_email': beneficiaireEmail,
        'payeur_nom': payeurNom,
        'payeur_email': payeurEmail,
      };
}
