import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxilife/core/api/api_client.dart';
import 'package:proxilife/core/theme/app_theme.dart';
import 'package:proxilife/features/teledoc/domain/teledoc_formatters.dart';
import 'package:proxilife/features/teledoc/domain/teledoc_location.dart';
import 'package:proxilife/features/teledoc/presentation/screens/patient/teledoc_consultation_detail_screen.dart';
import 'package:proxilife/features/teledoc/presentation/screens/patient/teledoc_pharmacy_screen.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import 'teledoc_fakes.dart';

Widget wrap(Widget child) => MaterialApp(theme: AppTheme.light(), home: child);

/// GPS fake: a fixed position, or a [TeledocLocationIssue].
class FakeLocation implements TeledocLocationProvider {
  FakeLocation({this.position, this.issue});

  final TeledocPosition? position;
  final TeledocLocationIssue? issue;
  final List<TeledocLocationIssue> settingsOpened = [];

  @override
  Future<TeledocPosition> current() async {
    final failure = issue;
    if (failure != null) throw TeledocLocationException(failure);
    return position!;
  }

  @override
  Future<void> openSettings(TeledocLocationIssue issue) async =>
      settingsOpened.add(issue);
}

TeledocPharmacyDto pharmacy(int id, String nom, double km) =>
    TeledocPharmacyDto(
      id: id,
      nom: nom,
      adresse: '$id avenue de Carthage, Tunis',
      telephone: '71 000 00$id',
      latitude: 36.8 + id / 100,
      longitude: 10.18,
      deGarde: true,
      distanceKm: km,
    );

void main() {
  test('teledocDistance : mètres, puis kilomètres avec virgule', () {
    expect(teledocDistance(null), '—');
    expect(teledocDistance(0.004), '0 m');
    expect(teledocDistance(0.847), '850 m');
    expect(teledocDistance(1.25), '1,3 km');
    expect(teledocDistance(12), '12,0 km');
  });

  test('liens : geo:, itinéraire OpenStreetMap, téléphone', () {
    final p = pharmacy(2, 'Pharmacie du Lac', 1);
    expect(
      TeledocPharmacyLinks.mapsApp(p).toString(),
      'geo:36.82,10.18?q=36.82,10.18(Pharmacie%20du%20Lac)',
    );
    final web = TeledocPharmacyLinks.webDirections(
      const TeledocPosition(36.8, 10.1),
      p,
    );
    expect(web.host, 'www.openstreetmap.org');
    expect(web.queryParameters['route'], '36.8,10.1;36.82,10.18');
    expect(TeledocPharmacyLinks.phone('71 000 002').toString(), 'tel:71000002');
  });

  group('Écran pharmacies de garde', () {
    late FakeTeledocRepository repo;
    late RecordingLinkOpener opener;

    setUp(() {
      repo = FakeTeledocRepository()
        ..pharmacies = [
          pharmacy(1, 'Pharmacie de La Marsa', 0.6),
          pharmacy(2, 'Pharmacie du Lac', 3.2),
        ]
        ..consultationList = [
          fakeConsultation(id: 9, ended: true, ordonnance: 'Repos'),
        ];
      opener = RecordingLinkOpener();
    });

    Future<void> open(
      WidgetTester tester, {
      required TeledocLocationProvider location,
      int? consultationId,
    }) async {
      await tester.pumpWidget(
        wrap(
          TeledocPharmacyScreen(
            repository: repo,
            consultationId: consultationId,
            location: location,
            linkOpener: opener,
            showMap: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('recherche depuis la position GPS, triée par distance', (
      tester,
    ) async {
      await open(
        tester,
        location: FakeLocation(position: const TeledocPosition(36.87, 10.32)),
      );
      expect(repo.lastPayload, {'lat': 36.87, 'lng': 10.32});
      expect(find.text('Pharmacie de La Marsa'), findsOneWidget);
      expect(find.text('600 m'), findsOneWidget);
      expect(find.text('3,2 km'), findsOneWidget);
      // Browse mode (no consultation): nothing to send.
      expect(find.text('Envoyer mon ordonnance ici'), findsNothing);
      expect(find.textContaining('Tunis centre'), findsNothing);
    });

    testWidgets('GPS refusé : repli sur Tunis centre, bouton Réglages', (
      tester,
    ) async {
      final location = FakeLocation(issue: TeledocLocationIssue.deniedForever);
      await open(tester, location: location);
      expect(repo.lastPayload, {
        'lat': teledocTunisCentre.latitude,
        'lng': teledocTunisCentre.longitude,
      });
      expect(find.textContaining('Tunis centre'), findsOneWidget);
      await tester.tap(find.text('Réglages'));
      expect(location.settingsOpened, [TeledocLocationIssue.deniedForever]);
      // The list is still usable.
      expect(find.text('Pharmacie du Lac'), findsOneWidget);
    });

    testWidgets('itinéraire : app de cartes, sinon OpenStreetMap web', (
      tester,
    ) async {
      await open(
        tester,
        location: FakeLocation(position: const TeledocPosition(36.87, 10.32)),
      );
      await tester.tap(find.text('Itinéraire').first);
      await tester.pump();
      expect(opener.opened.single.scheme, 'geo');

      opener
        ..opened.clear()
        ..succeeds = false;
      await tester.tap(find.text('Itinéraire').first);
      await tester.pump();
      expect(opener.opened.map((u) => u.scheme), ['geo', 'https']);
      await tester.pump();
      expect(
        find.text('Aucune application de cartes disponible'),
        findsOneWidget,
      );
    });

    testWidgets('appeler ouvre le composeur', (tester) async {
      await open(
        tester,
        location: FakeLocation(position: const TeledocPosition(36.87, 10.32)),
      );
      await tester.tap(find.text('Appeler').first);
      await tester.pump();
      expect(opener.opened.single.toString(), 'tel:71000001');
    });

    testWidgets('envoyer l\'ordonnance : appel API puis retour', (
      tester,
    ) async {
      TeledocConsultationDto? result;
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await Navigator.of(context)
                      .push<TeledocConsultationDto>(
                        MaterialPageRoute(
                          builder: (_) => TeledocPharmacyScreen(
                            repository: repo,
                            consultationId: 9,
                            location: FakeLocation(
                              position: const TeledocPosition(36.87, 10.32),
                            ),
                            linkOpener: opener,
                            showMap: false,
                          ),
                        ),
                      );
                },
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Ouvrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Envoyer mon ordonnance ici').last);
      await tester.pumpAndSettle();
      expect(repo.calls, contains('choosePharmacy 9 2'));
      expect(find.byType(TeledocPharmacyScreen), findsNothing);
      expect(result?.pharmacieNom, 'Pharmacie du Lac');
      expect(
        find.text('Ordonnance envoyée à Pharmacie du Lac'),
        findsOneWidget,
      );
    });

    testWidgets('refus du serveur (pharmacie fermée) : message', (
      tester,
    ) async {
      await open(
        tester,
        location: FakeLocation(position: const TeledocPosition(36.87, 10.32)),
        consultationId: 9,
      );
      repo.nextError = ApiException(
        409,
        'Cette pharmacie n\'est pas de garde : choisissez-en une autre',
      );
      await tester.tap(find.text('Envoyer mon ordonnance ici').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('pas de garde'), findsOneWidget);
      expect(find.byType(TeledocPharmacyScreen), findsOneWidget);
    });

    testWidgets('aucune pharmacie de garde : message clair', (tester) async {
      repo.pharmacies = [];
      await open(
        tester,
        location: FakeLocation(position: const TeledocPosition(36.87, 10.32)),
      );
      expect(
        find.text('Aucune pharmacie de garde trouvée pour le moment.'),
        findsOneWidget,
      );
    });
  });

  testWidgets('consultation terminée : accès aux pharmacies de garde', (
    tester,
  ) async {
    final repo = FakeTeledocRepository()
      ..consultationList = [
        fakeConsultation(id: 9, ended: true, ordonnance: 'Repos'),
      ];
    await tester.pumpWidget(
      wrap(
        TeledocConsultationDetailScreen(repository: repo, consultationId: 9),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Trouver une pharmacie de garde'), findsOneWidget);
  });
}
