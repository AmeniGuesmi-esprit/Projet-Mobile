import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proxilife/core/api/api_client.dart';
import 'package:proxilife/core/session/session_controller.dart';
import 'package:proxilife/features/foodsave/client/my_reservations_screen.dart';
import 'package:proxilife/features/foodsave/client/reservation_qr_screen.dart';
import 'package:proxilife/features/foodsave/data/reservation_cache.dart';
import 'package:proxilife/features/foodsave/data/sqflite_reservation_cache.dart';
import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../fakes.dart';

String _iso(DateTime d) => d.toUtc().toIso8601String();

final DateTime _t0 = DateTime.utc(2026, 10, 13, 17);

Map<String, dynamic> _reservationJson({
  int id = 9,
  String statut = 'en_attente',
  String? token = 'FS1.9.bm9uY2U.c2ln',
  String titre = 'Panier du soir',
  Duration age = const Duration(minutes: 20),
}) => {
  'id': id,
  'date': _iso(_t0.subtract(age)),
  'statut': statut,
  'panier_id': 5,
  'client_id': 3,
  'quantite_reservee': 2,
  'montant_centimes': 1000,
  'mode_paiement': 'portefeuille',
  'moyen_paiement_id': 2,
  'statut_paiement': 'paye',
  'transaction_id': 44,
  'facture_numero': null,
  'date_creation_qr': _iso(_t0.subtract(const Duration(minutes: 17))),
  'date_expiration_qr': _iso(_t0.add(const Duration(minutes: 12))),
  'qr_token': token,
  'retire_le': null,
  'panier': {
    'id': 5,
    'titre': titre,
    'contenu': 'Pains, viennoiseries',
    'categorie': 'boulangerie',
    'image': null,
    'prix_centimes': 500,
    'prix_initial_centimes': 1500,
    'quantite': 3,
    'quantite_initiale': 10,
    'creneau_retrait_debut': _iso(_t0),
    'creneau_retrait_fin': _iso(_t0.add(const Duration(hours: 2))),
    'date_expiration': _iso(_t0.add(const Duration(hours: 3))),
    'statut': 'disponible',
    'commercant_id': 7,
    'cree_le': _iso(_t0.subtract(const Duration(hours: 1))),
    'commerce': {
      'id': 1,
      'commercant_id': 7,
      'nom': 'Boulangerie du Lac',
      'adresse': '12 rue du Lac, Tunis',
      'latitude': 36.83,
      'longitude': 10.23,
      'categorie': 'boulangerie',
    },
  },
  'client_nom': null,
};

ReservationDto _reservation({int id = 9, String titre = 'Panier du soir'}) =>
    ReservationDto.fromJson(_reservationJson(id: id, titre: titre));

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// Server that answers normally while [up] is true, and is unreachable
/// (network error) otherwise.
class _Server {
  bool up = true;
  List<Map<String, dynamic>> reservations = [];
  Map<String, dynamic> reservation = _reservationJson();
  int status = 200;

  late final MockClient client = MockClient((request) async {
    if (!up) throw http.ClientException('Réseau indisponible');
    if (status != 200) return _json({'error': 'Introuvable'}, status);
    final path = request.url.path;
    if (path == '/foodsave/reservations') {
      return _json({'items': reservations});
    }
    if (path.startsWith('/foodsave/reservations/')) return _json(reservation);
    return _json({'error': 'Introuvable'}, 404);
  });
}

SessionController _session(_Server server) {
  final session = makeTestSession(
    api: ApiClient(httpClient: server.client, baseUrl: 'http://fake'),
  );
  session.user = const UserDto(
    id: 3,
    nom: 'Guesmi',
    prenom: 'Ameni',
    email: 'ameni@example.com',
    telephone: '+21620000000',
    role: UserRole.client,
    statutCompte: AccountStatus.actif,
    soldeCentimes: 2000,
  );
  return session;
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
}

const _bannerKey = ValueKey('foodsave-offline-banner');

void main() {
  sqfliteFfiInit();

  group('Base locale sqflite des réservations', () {
    late SqfliteReservationCache cache;

    setUp(() {
      cache = SqfliteReservationCache(
        factory: databaseFactoryFfiNoIsolate,
        path: inMemoryDatabasePath,
      );
    });

    tearDown(() => cache.close());

    test('enregistre, relit (QR, panier, commerce) et met à jour', () async {
      await cache.save(3, _reservation());
      final r = (await cache.byId(3, 9))!;
      expect(r.qrToken, 'FS1.9.bm9uY2U.c2ln');
      expect(r.panier!.titre, 'Panier du soir');
      expect(r.panier!.commerce!.nom, 'Boulangerie du Lac');

      // Même id : mise à jour, pas de doublon.
      await cache.save(3, _reservation(titre: 'Panier du midi'));
      final all = await cache.all(3);
      expect(all, hasLength(1));
      expect(all.single.panier!.titre, 'Panier du midi');
    });

    test('remplace toute la liste, la plus récente en premier', () async {
      await cache.save(3, _reservation(id: 1));
      await cache.replaceAll(3, [
        ReservationDto.fromJson(
          _reservationJson(id: 20, age: const Duration(hours: 2)),
        ),
        ReservationDto.fromJson(_reservationJson(id: 21)),
      ]);
      expect((await cache.all(3)).map((r) => r.id), [21, 20]);

      await cache.replaceAll(3, []);
      expect(await cache.all(3), isEmpty);
    });

    test('chaque compte ne voit que ses réservations', () async {
      await cache.save(3, _reservation(id: 9));
      await cache.save(4, _reservation(id: 10));
      expect((await cache.all(3)).map((r) => r.id), [9]);
      expect(await cache.byId(3, 10), isNull);
    });
  });

  group('Mes réservations hors ligne', () {
    testWidgets('en ligne : la liste est enregistrée sur le téléphone', (
      tester,
    ) async {
      _phone(tester);
      final server = _Server()..reservations = [_reservationJson()];
      final cache = MemoryReservationCache();
      await tester.pumpWidget(
        MaterialApp(
          home: MyReservationsScreen(
            session: _session(server),
            clock: () => _t0,
            cache: cache,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Panier du soir'), findsOneWidget);
      expect(find.byKey(_bannerKey), findsNothing);
      expect((await cache.all(3)).map((r) => r.id), [9]);
    });

    testWidgets('serveur injoignable : copie locale + bandeau', (tester) async {
      _phone(tester);
      final server = _Server()..up = false;
      final cache = MemoryReservationCache();
      await cache.replaceAll(3, [_reservation()]);
      await tester.pumpWidget(
        MaterialApp(
          home: MyReservationsScreen(
            session: _session(server),
            clock: () => _t0,
            cache: cache,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(_bannerKey), findsOneWidget);
      expect(find.text('Panier du soir'), findsOneWidget);
    });

    testWidgets('serveur injoignable et rien sur le téléphone : erreur', (
      tester,
    ) async {
      _phone(tester);
      final server = _Server()..up = false;
      await tester.pumpWidget(
        MaterialApp(
          home: MyReservationsScreen(
            session: _session(server),
            clock: () => _t0,
            cache: MemoryReservationCache(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(_bannerKey), findsNothing);
      expect(find.text('Réessayer'), findsOneWidget);
    });
  });

  group('QR code hors ligne', () {
    testWidgets('le QR reste affiché sans réseau, sans bouton Annuler', (
      tester,
    ) async {
      _phone(tester);
      final server = _Server()..up = false;
      final cache = MemoryReservationCache();
      await cache.save(3, _reservation());
      await tester.pumpWidget(
        MaterialApp(
          home: ReservationQrScreen(
            session: _session(server),
            reservationId: 9,
            clock: () => _t0,
            cache: cache,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(_bannerKey), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Annuler la réservation'), findsNothing);
    });

    testWidgets('un refus du serveur (404) n’est pas masqué par la copie', (
      tester,
    ) async {
      _phone(tester);
      final server = _Server()..status = 404;
      final cache = MemoryReservationCache();
      await cache.save(3, _reservation());
      await tester.pumpWidget(
        MaterialApp(
          home: ReservationQrScreen(
            session: _session(server),
            reservationId: 9,
            clock: () => _t0,
            cache: cache,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(_bannerKey), findsNothing);
      expect(find.byType(QrImageView), findsNothing);
    });
  });
}
