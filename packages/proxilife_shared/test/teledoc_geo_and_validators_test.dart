import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:test/test.dart';

void main() {
  group('GeoDistance.haversineKm', () {
    test('distance nulle pour un même point', () {
      expect(GeoDistance.haversineKm(36.8, 10.18, 36.8, 10.18), 0);
    });

    test('Tunis centre → La Marsa ≈ 16 km', () {
      // Avenue Habib Bourguiba → centre de La Marsa.
      final d = GeoDistance.haversineKm(36.8008, 10.1800, 36.8782, 10.3247);
      expect(d, closeTo(15.5, 1.0));
    });

    test('Paris → Tunis ≈ 1 480 km (référence connue)', () {
      final d = GeoDistance.haversineKm(48.8566, 2.3522, 36.8065, 10.1815);
      expect(d, closeTo(1480, 15));
    });

    test('symétrique', () {
      final a = GeoDistance.haversineKm(36.85, 10.2, 36.75, 10.25);
      final b = GeoDistance.haversineKm(36.75, 10.25, 36.85, 10.2);
      expect(a, closeTo(b, 1e-9));
    });

    test('bornes des coordonnées', () {
      expect(GeoDistance.isValidLatitude(90), isTrue);
      expect(GeoDistance.isValidLatitude(90.1), isFalse);
      expect(GeoDistance.isValidLongitude(-180), isTrue);
      expect(GeoDistance.isValidLongitude(181), isFalse);
      expect(GeoDistance.isValidLatitude(double.nan), isFalse);
    });
  });

  group('validateurs TeleDoc', () {
    test('motif : 3 à 80 caractères, espaces ignorés', () {
      expect(teledocMotifError('Fièvre'), isNull);
      expect(teledocMotifError('  '), 'Motif obligatoire');
      expect(teledocMotifError(null), 'Motif obligatoire');
      expect(teledocMotifError(' ab '), contains('au moins 3'));
      expect(teledocMotifError('x' * 81), contains('80'));
    });

    test('description : 10 à 1000 caractères', () {
      expect(teledocDescriptionError('Toux sèche depuis 3 jours'), isNull);
      expect(teledocDescriptionError('Toux'), contains('au moins 10'));
      expect(teledocDescriptionError('x' * 1001), contains('1000'));
    });

    test('ordonnance : 3 à 2000 caractères', () {
      expect(teledocOrdonnanceError('Paracétamol 1 g, 3 fois par jour'),
          isNull);
      expect(teledocOrdonnanceError(''), 'Ordonnance obligatoire');
      expect(teledocOrdonnanceError('x' * 2001), contains('2000'));
    });

    test('tarif : 30 DT en centimes', () {
      expect(TeledocPricing.consultationCents, 3000);
      expect(isValidAmountCents(TeledocPricing.consultationCents), isTrue);
    });
  });

  test('DTO demande : aller-retour JSON', () {
    const dto = TeledocRequestDto(
      id: 1,
      motif: 'Fièvre',
      description: 'Fièvre à 39 °C depuis hier',
      urgence: TeledocUrgency.moyenne,
      aPhoto: true,
      statut: TeledocRequestStatus.enAttente,
      positionFile: 2,
      tempsEstimeMinutes: 15,
      creeLe: '2026-10-14T09:00:00.000',
      modifieLe: '2026-10-14T09:00:00.000',
    );
    final back = TeledocRequestDto.fromJson(dto.toJson());
    expect(back.toJson(), dto.toJson());
  });
}
