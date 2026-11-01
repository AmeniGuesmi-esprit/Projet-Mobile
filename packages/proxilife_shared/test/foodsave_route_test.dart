import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:test/test.dart';

void main() {
  test('TravelMode parses its api values and labels in French', () {
    expect(TravelMode.parse('voiture'), TravelMode.voiture);
    expect(TravelMode.parse('pied'), TravelMode.pied);
    expect(TravelMode.pied.label, 'À pied');
    expect(() => TravelMode.parse('velo'), throwsArgumentError);
  });

  test('RouteDto JSON round trip', () {
    const route = RouteDto(
      mode: TravelMode.pied,
      distanceMetres: 4644,
      dureeSecondes: 3714,
      points: [(36.8064, 10.1814), (36.7751, 10.1718)],
    );
    final copy = RouteDto.fromJson(route.toJson());
    expect(copy.mode, TravelMode.pied);
    expect(copy.distanceMetres, 4644);
    expect(copy.dureeSecondes, 3714);
    expect(copy.points, route.points);
    // Server may send doubles for distance / duration.
    expect(
        RouteDto.fromJson({
          'mode': 'voiture',
          'distance_m': 5295.4,
          'duree_s': 396.6,
          'points': [
            [36.8, 10.18],
          ],
        }).dureeSecondes,
        397);
  });
}
