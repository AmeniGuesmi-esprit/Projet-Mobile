import '../enums.dart';

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
    this.beneficiaireNom,
    this.beneficiaireEmail,
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
  final String? beneficiaireNom;
  final String? beneficiaireEmail;

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
        beneficiaireNom: json['beneficiaire_nom'] as String?,
        beneficiaireEmail: json['beneficiaire_email'] as String?,
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
        'beneficiaire_nom': beneficiaireNom,
        'beneficiaire_email': beneficiaireEmail,
      };
}
