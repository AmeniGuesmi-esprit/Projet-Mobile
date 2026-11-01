import '../enums.dart';

/// A stored payment method. Card data is intentionally limited to the last
/// four digits (full numbers are never stored).
class PaymentMethodDto {
  const PaymentMethodDto({
    required this.id,
    required this.type,
    required this.parDefaut,
    this.quatreDerniersChiffres,
    this.nomTitulaire,
    this.dateExpiration,
  });

  final int id;
  final PaymentMethodType type;
  final String? quatreDerniersChiffres;
  final String? nomTitulaire;
  final String? dateExpiration;
  final bool parDefaut;

  factory PaymentMethodDto.fromJson(Map<String, dynamic> json) =>
      PaymentMethodDto(
        id: json['id'] as int,
        type: PaymentMethodType.parse(json['type'] as String),
        quatreDerniersChiffres: json['quatre_derniers_chiffres'] as String?,
        nomTitulaire: json['nom_titulaire'] as String?,
        dateExpiration: json['date_expiration'] as String?,
        parDefaut: json['par_defaut'] as bool,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.apiValue,
        'quatre_derniers_chiffres': quatreDerniersChiffres,
        'nom_titulaire': nomTitulaire,
        'date_expiration': dateExpiration,
        'par_defaut': parDefaut,
      };
}
