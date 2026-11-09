import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxilife/core/api/api_client.dart';
import 'package:proxilife/features/teledoc/data/sqflite_teledoc_history_store.dart';
import 'package:proxilife/features/teledoc/data/teledoc_offline_repository.dart';
import 'package:proxilife/features/teledoc/presentation/screens/patient/teledoc_patient_home_screen.dart';
import 'package:proxilife/features/teledoc/presentation/teledoc_theme.dart';
import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'teledoc_fakes.dart';

const _offline = ApiException(0, 'Serveur local indisponible');

void main() {
  sqfliteFfiInit();

  late SqfliteTeledocHistoryStore store;

  setUp(() {
    store = SqfliteTeledocHistoryStore(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
  });

  tearDown(() => store.close());

  group('Base locale sqflite', () {
    test('CRUD : enregistrer, lire, mettre à jour, supprimer', () async {
      final c = fakeConsultation(id: 7, ended: true, ordonnance: 'Repos');
      await store.save(1, c);
      expect((await store.byId(1, 7))!.ordonnance, 'Repos');

      // Même id : mise à jour, pas de doublon.
      await store.save(1, fakeConsultation(id: 7, ended: true, ordonnance: 'Eau'));
      final all = await store.all(1);
      expect(all, hasLength(1));
      expect(all.single.ordonnance, 'Eau');

      await store.delete(1, 7);
      expect(await store.all(1), isEmpty);
    });

    test('la salle d\'appel secrète n\'est jamais enregistrée', () async {
      await store.save(1, fakeConsultation(id: 3));
      expect(fakeConsultation(id: 3).salleAppel, isNotNull);
      expect((await store.byId(1, 3))!.salleAppel, isNull);
    });

    test('chaque compte ne voit que son historique', () async {
      await store.save(1, fakeConsultation(id: 1));
      await store.save(2, fakeConsultation(id: 2));
      expect((await store.all(1)).map((c) => c.id), [1]);
      expect(await store.byId(1, 2), isNull);
    });

    test('replaceAll remplace tout l\'historique du compte', () async {
      await store.save(1, fakeConsultation(id: 1));
      await store.save(2, fakeConsultation(id: 9));
      await store.replaceAll(1, [
        fakeConsultation(id: 4, ended: true),
        fakeConsultation(id: 5, ended: true),
      ]);
      expect((await store.all(1)).map((c) => c.id).toSet(), {4, 5});
      expect(await store.all(2), hasLength(1), reason: 'autre compte intact');
    });
  });

  group('Dépôt hors ligne', () {
    late FakeTeledocRepository remote;
    late TeledocOfflineRepository repo;

    setUp(() {
      remote = FakeTeledocRepository()
        ..consultationList = [
          fakeConsultation(id: 7, ended: true, ordonnance: 'Paracétamol'),
        ];
      repo = TeledocOfflineRepository(remote, store, 1);
    });

    test('en ligne : la liste du serveur est copiée sur le téléphone',
        () async {
      expect(await repo.consultations(), hasLength(1));
      expect(repo.servingCachedHistory.value, isFalse);
      expect((await store.byId(1, 7))!.ordonnance, 'Paracétamol');
    });

    test('hors ligne : l\'historique et l\'ordonnance viennent de sqflite',
        () async {
      await repo.consultations();

      remote.nextError = _offline;
      final list = await repo.consultations();
      expect(list.single.ordonnance, 'Paracétamol');
      expect(repo.servingCachedHistory.value, isTrue);

      remote.nextError = _offline;
      expect((await repo.consultation(7)).ordonnance, 'Paracétamol');

      // Le serveur revient : on repasse en ligne.
      await repo.consultations();
      expect(repo.servingCachedHistory.value, isFalse);
    });

    test('hors ligne sans copie locale : l\'erreur réseau est affichée',
        () async {
      remote.nextError = _offline;
      await expectLater(repo.consultations(), throwsA(_offline));
    });

    test('un refus du serveur (4xx) ne bascule jamais en local', () async {
      await repo.consultations();
      remote.nextError = const ApiException(403, 'Accès refusé');
      await expectLater(
        repo.consultations(),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'code', 403)),
      );
    });

    test('fin de consultation et suppression mettent la copie à jour',
        () async {
      remote.consultationList = [fakeConsultation(id: 8)];
      await repo.consultations();
      await repo.endConsultation(8, 'Ordonnance finale');
      expect((await store.byId(1, 8))!.ordonnance, 'Ordonnance finale');
      await repo.deleteConsultation(8);
      expect(await store.byId(1, 8), isNull);
    });
  });

  testWidgets('écran patient : bandeau « Mode hors ligne »', (tester) async {
    final remote = _SwitchableServer()
      ..consultationList = [
        fakeConsultation(id: 7, ended: true, ordonnance: 'Paracétamol'),
      ];
    final repo = TeledocOfflineRepository(remote, store, 1);
    await tester.runAsync(() => repo.consultations()); // copie locale

    remote.down = true; // le serveur s'arrête
    await tester.pumpWidget(MaterialApp(
      home: TeledocThemed(
        child: TeledocPatientHomeScreen(
          session: teledocSession(UserRole.client),
          repository: repo,
        ),
      ),
    ));
    // sqflite répond hors de la zone de test : on lui laisse le temps.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.tap(find.text('Mes consultations'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Mode hors ligne'), findsOneWidget);
    expect(find.text('Fièvre'), findsOneWidget);
  });
}

/// Fake server that can be switched off (every call is a network error).
class _SwitchableServer extends FakeTeledocRepository {
  bool down = false;

  @override
  Future<List<TeledocRequestDto>> myRequests({
    TeledocRequestStatus? statut,
  }) async {
    if (down) throw _offline;
    return super.myRequests(statut: statut);
  }

  @override
  Future<List<TeledocConsultationDto>> consultations() async {
    if (down) throw _offline;
    return super.consultations();
  }
}
