/// A vehicle owned by a driver. [nbPlaces] is the number of passenger seats.
class VehicleDto {
  const VehicleDto({
    required this.id,
    required this.marque,
    required this.modele,
    required this.couleur,
    required this.nbPlaces,
  });

  final int id;
  final String marque;
  final String modele;
  final String couleur;
  final int nbPlaces;

  factory VehicleDto.fromJson(Map<String, dynamic> json) => VehicleDto(
        id: json['id'] as int,
        marque: json['marque'] as String,
        modele: json['modele'] as String,
        couleur: json['couleur'] as String,
        nbPlaces: json['nb_places'] as int,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'marque': marque,
        'modele': modele,
        'couleur': couleur,
        'nb_places': nbPlaces,
      };

  /// e.g. "Peugeot 208 · Gris"
  String get libelle => '$marque $modele · $couleur';
}
