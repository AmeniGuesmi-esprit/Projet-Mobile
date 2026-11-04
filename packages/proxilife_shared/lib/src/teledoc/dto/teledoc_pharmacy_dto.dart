/// A pharmacy; [distanceKm] is only set by the "nearest on-duty" search.
class TeledocPharmacyDto {
  const TeledocPharmacyDto({
    required this.id,
    required this.nom,
    required this.adresse,
    required this.telephone,
    required this.latitude,
    required this.longitude,
    required this.deGarde,
    this.distanceKm,
  });

  final int id;
  final String nom;
  final String adresse;
  final String telephone;
  final double latitude;
  final double longitude;
  final bool deGarde;
  final double? distanceKm;

  factory TeledocPharmacyDto.fromJson(Map<String, dynamic> json) =>
      TeledocPharmacyDto(
        id: json['id'] as int,
        nom: json['nom'] as String,
        adresse: json['adresse'] as String,
        telephone: json['telephone'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        deGarde: json['de_garde'] as bool,
        distanceKm: (json['distance_km'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nom': nom,
        'adresse': adresse,
        'telephone': telephone,
        'latitude': latitude,
        'longitude': longitude,
        'de_garde': deGarde,
        'distance_km': distanceKm,
      };
}
