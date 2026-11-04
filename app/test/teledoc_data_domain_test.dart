import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proxilife/core/api/api_client.dart';
import 'package:proxilife/features/teledoc/data/teledoc_api_repository.dart';
import 'package:proxilife/features/teledoc/domain/teledoc_formatters.dart';
import 'package:proxilife/features/teledoc/domain/teledoc_queue_tracker.dart';
import 'package:proxilife/features/teledoc/presentation/controllers/teledoc_queue_controller.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import 'teledoc_fakes.dart';

void main() {
  group('TeledocQueueTracker', () {
    test('« bientôt » une seule fois, même si une urgence fait reculer', () {
      final tracker = TeledocQueueTracker();
      expect(tracker.update(fakeStatus(position: 4)), isEmpty);
      expect(tracker.update(fakeStatus(position: 2)), [TeledocQueueEvent.soon]);
      expect(tracker.update(fakeStatus(position: 3)), isEmpty);
      expect(tracker.update(fakeStatus(position: 1)), isEmpty);
    });

    test('« le médecin vous attend » au passage en consultation', () {
      final tracker = TeledocQueueTracker()..update(fakeStatus(position: 5));
      expect(tracker.update(fakeStatus(statut: TeledocRequestStatus.enCours)), [
        TeledocQueueEvent.started,
      ]);
    });

    test(
      'écran ouvert sur une consultation déjà commencée : pas de doublon',
      () {
        final tracker = TeledocQueueTracker();
        expect(
          tracker.update(fakeStatus(statut: TeledocRequestStatus.enCours)),
          isEmpty,
        );
      },
    );

    test('annulation détectée', () {
      final tracker = TeledocQueueTracker()..update(fakeStatus(position: 5));
      expect(tracker.update(fakeStatus(statut: TeledocRequestStatus.annulee)), [
        TeledocQueueEvent.cancelled,
      ]);
    });

    test('textes de notification en français', () {
      expect(
        teledocNotificationText(
          TeledocQueueEvent.soon,
          fakeStatus(position: 1),
        ).body,
        contains('le prochain patient'),
      );
      expect(
        teledocNotificationText(
          TeledocQueueEvent.soon,
          fakeStatus(position: 2),
        ).body,
        contains('Plus que 1 patient'),
      );
      expect(
        teledocNotificationText(
          TeledocQueueEvent.started,
          fakeStatus(
            statut: TeledocRequestStatus.enCours,
            type: TeledocConsultationType.audio,
          ),
        ).body,
        contains('audio'),
      );
    });
  });

  group('Formatage', () {
    test('dates, attente, position, durée', () {
      expect(teledocDate('2026-10-04T09:05:00.000'), '04/10/2026 09:05');
      expect(teledocWaitLabel(0), 'Moins de 5 min');
      expect(teledocWaitLabel(30), 'Environ 30 min');
      expect(teledocWaitLabel(90), 'Environ 1 h 30');
      expect(teledocWaitLabel(120), 'Environ 2 h');
      expect(teledocPositionLabel(1), '1er');
      expect(teledocPositionLabel(3), '3e');
      expect(
        teledocDuration('2026-10-14T09:30:00', '2026-10-14T09:48:00'),
        '18 min',
      );
      expect(teledocDuration('2026-10-14T09:30:00', null), '—');
    });
  });

  group('TeledocApiRepository (HTTP simulé)', () {
    late List<http.Request> sent;

    TeledocApiRepository repositoryReturning(Object body, {int status = 200}) {
      sent = [];
      final client = ApiClient(
        httpClient: MockClient((request) async {
          sent.add(request);
          return http.Response(
            jsonEncode(body),
            status,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
        baseUrl: 'http://srv',
      )..token = 'tok';
      return TeledocApiRepository(client);
    }

    test('création : photo encodée en base64, jeton envoyé', () async {
      final repo = repositoryReturning(fakeRequest(id: 5).toJson());
      final created = await repo.createRequest(
        motif: 'Fièvre',
        description: 'Fièvre à 39 °C depuis hier soir',
        urgence: TeledocUrgency.elevee,
        photoBytes: [0xFF, 0xD8, 0xFF],
      );
      expect(created.id, 5);
      final request = sent.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'http://srv/teledoc/requests');
      expect(request.headers['authorization'], 'Bearer tok');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['urgence'], 'elevee');
      expect(base64Decode(body['photo_base64'] as String), [0xFF, 0xD8, 0xFF]);
    });

    test('modification : seuls les champs fournis partent', () async {
      final repo = repositoryReturning(fakeRequest(id: 5).toJson());
      await repo.updateRequest(5, motif: 'Toux', removePhoto: true);
      final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
      expect(body, {'motif': 'Toux', 'supprimer_photo': true});
      expect(sent.single.method, 'PATCH');
    });

    test('pharmacies : coordonnées en paramètres', () async {
      final repo = repositoryReturning({'items': []});
      await repo.nearestPharmacies(lat: 36.8, lng: 10.18, limit: 3);
      expect(sent.single.url.queryParameters, {
        'lat': '36.8',
        'lng': '10.18',
        'limit': '3',
      });
    });

    test('erreur serveur : message français remonté', () async {
      final repo = repositoryReturning({
        'error': 'Vous avez déjà une demande en cours',
      }, status: 409);
      expect(
        () => repo.myRequests(),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 409)
              .having((e) => e.message, 'message', contains('déjà')),
        ),
      );
    });

    test('URL de photo : authentifiée et invalidée après modification', () {
      final repo = repositoryReturning({});
      final source = repo.photoOf(fakeRequest(id: 9));
      expect(source.url, startsWith('http://srv/teledoc/requests/9/photo?v='));
      expect(source.headers['authorization'], 'Bearer tok');
    });
  });

  group('TeledocQueueController (polling)', () {
    testWidgets('interroge toutes les 5 s puis s\'arrête en consultation', (
      tester,
    ) async {
      final repo = FakeTeledocRepository()
        ..statuses = [
          fakeStatus(position: 3),
          fakeStatus(position: 2),
          fakeStatus(
            statut: TeledocRequestStatus.enCours,
            consultationId: 7,
            type: TeledocConsultationType.video,
          ),
        ];
      final notifier = RecordingNotifier();
      final controller = TeledocQueueController(
        repository: repo,
        requestId: 1,
        notifier: notifier,
      )..start();

      await tester.pump();
      expect(controller.status!.positionFile, 3);
      expect(controller.isPolling, isTrue);

      await tester.pump(const Duration(seconds: 5));
      expect(controller.status!.positionFile, 2);
      expect(notifier.events, [TeledocQueueEvent.soon]);

      await tester.pump(const Duration(seconds: 5));
      expect(controller.status!.statut, TeledocRequestStatus.enCours);
      expect(notifier.events.last, TeledocQueueEvent.started);
      expect(controller.isPolling, isFalse);

      await tester.pump(const Duration(seconds: 30));
      expect(repo.queueStatusCalls, 3, reason: 'plus de polling');
      controller.dispose();
    });

    testWidgets('erreur réseau : garde le dernier état et continue', (
      tester,
    ) async {
      final repo = FakeTeledocRepository()..statuses = [fakeStatus()];
      final controller = TeledocQueueController(
        repository: repo,
        requestId: 1,
        notifier: RecordingNotifier(),
      )..start();
      await tester.pump();

      repo.nextError = const ApiException(0, 'Serveur local indisponible');
      await tester.pump(const Duration(seconds: 5));
      expect(controller.error, 'Serveur local indisponible');
      expect(controller.status, isNotNull);
      expect(controller.isPolling, isTrue);

      await tester.pump(const Duration(seconds: 5));
      expect(controller.error, isNull);
      controller.dispose();
    });

    testWidgets('dispose arrête le timer', (tester) async {
      final repo = FakeTeledocRepository()..statuses = [fakeStatus()];
      final controller = TeledocQueueController(
        repository: repo,
        requestId: 1,
        notifier: RecordingNotifier(),
      )..start();
      await tester.pump();
      controller.dispose();
      await tester.pump(const Duration(seconds: 20));
      expect(repo.queueStatusCalls, 1);
    });
  });
}
