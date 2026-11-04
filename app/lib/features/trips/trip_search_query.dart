import '../../core/location/geocoding_service.dart';

/// What the passenger typed in the search screen.
class TripSearchQuery {
  const TripSearchQuery({
    required this.depart,
    this.arrivee,
    this.rayonKm = 5,
    this.date,
    this.heure,
    this.fenetreMin = 60,
    this.places = 1,
    this.silence = false,
    this.nonFumeur = false,
    this.animaux = false,
    this.femmes = false,
  });

  final GeoPlace depart;
  final GeoPlace? arrivee;
  final double rayonKm;
  final DateTime? date;

  /// Desired departure time (day + hour). When set, the server only returns
  /// trips within ±[fenetreMin] minutes and ranks them by compatibility.
  final DateTime? heure;
  final int fenetreMin;
  final int places;
  final bool silence;
  final bool nonFumeur;
  final bool animaux;
  final bool femmes;

  String get queryString {
    String two(int n) => n.toString().padLeft(2, '0');
    final day = date;
    final dest = arrivee;
    final time = heure;
    return Uri(queryParameters: {
      'lat': '${depart.latitude}',
      'lng': '${depart.longitude}',
      if (dest != null) 'dest_lat': '${dest.latitude}',
      if (dest != null) 'dest_lng': '${dest.longitude}',
      'rayon_km': '${rayonKm.round()}',
      if (day != null) 'date': '${day.year}-${two(day.month)}-${two(day.day)}',
      if (time != null) 'heure': time.toIso8601String(),
      if (time != null) 'fenetre_min': '$fenetreMin',
      'places': '$places',
      if (silence) 'ambiance': 'silence',
      if (nonFumeur) 'non_fumeur': '1',
      if (animaux) 'animaux': '1',
      if (femmes) 'femmes': '1',
    }).query;
  }
}
