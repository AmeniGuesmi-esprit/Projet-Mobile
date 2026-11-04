import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxilife/core/api/api_client.dart';
import 'package:proxilife/core/theme/app_theme.dart';
import 'package:proxilife/features/teledoc/domain/teledoc_queue_tracker.dart';
import 'package:proxilife/features/teledoc/presentation/screens/patient/teledoc_queue_screen.dart';
import 'package:proxilife/features/teledoc/presentation/screens/teledoc_home_screen.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import 'fakes.dart';
import 'teledoc_fakes.dart';

void main() {
  late FakeTeledocRepository repo;
  late RecordingNotifier notifier;

  setUp(() {
    repo = FakeTeledocRepository();
    notifier = RecordingNotifier();
  });

  Future<void> openQueue(
    WidgetTester tester, {
    bool notificationsEnabled = true,
    Future<bool> Function()? enable,
  }) async {
    final session = teledocSession(UserRole.client);
    (session.settings as FakeSettingsStore).notifications =
        notificationsEnabled;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: TeledocQueueScreen(
          session: session,
          repository: repo,
          requestId: 1,
          notifier: notifier,
          enableNotifications: enable,
        ),
      ),
    );
    await tester.pump(); // first poll
    await tester.pump(); // settings read
  }

  testWidgets('position, taille et attente ; mise à jour toutes les 5 s', (
    tester,
  ) async {
    repo.statuses = [
      fakeStatus(position: 3, wait: 30),
      fakeStatus(position: 2, wait: 15),
    ];
    await openQueue(tester);
    expect(find.text('3e'), findsOneWidget);
    expect(find.text('sur 4 patients'), findsOneWidget);
    expect(find.text('Environ 30 min'), findsOneWidget);
    expect(find.textContaining('bientôt votre tour'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 400)); // AnimatedSwitcher
    expect(find.text('2e'), findsOneWidget);
    expect(find.textContaining('bientôt votre tour'), findsOneWidget);
    expect(notifier.events, [TeledocQueueEvent.soon]);
    expect(repo.queueStatusCalls, 2);
  });

  testWidgets('le médecin démarre : écran « Le médecin vous attend »', (
    tester,
  ) async {
    repo.statuses = [
      fakeStatus(position: 1, wait: 0),
      fakeStatus(
        statut: TeledocRequestStatus.enCours,
        consultationId: 7,
        type: TeledocConsultationType.video,
      ),
    ];
    await openQueue(tester);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('Le médecin vous attend'), findsOneWidget);
    expect(notifier.events, [
      TeledocQueueEvent.soon,
      TeledocQueueEvent.started,
    ]);

    await tester.pump(const Duration(seconds: 30));
    expect(repo.queueStatusCalls, 2, reason: 'polling arrêté');
  });

  testWidgets('perte de connexion : bandeau, dernière position conservée', (
    tester,
  ) async {
    repo.statuses = [fakeStatus(position: 3)];
    await openQueue(tester);
    repo.nextError = const ApiException(0, 'Serveur local indisponible');
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.textContaining('Connexion perdue'), findsOneWidget);
    expect(find.text('3e'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.textContaining('Connexion perdue'), findsNothing);
  });

  testWidgets('notifications désactivées : proposition d\'activation', (
    tester,
  ) async {
    repo.statuses = [fakeStatus(position: 4)];
    var asked = 0;
    await openQueue(
      tester,
      notificationsEnabled: false,
      enable: () async {
        asked++;
        return true;
      },
    );
    expect(find.text('Être prévenu de mon tour'), findsOneWidget);
    await tester.tap(find.text('Activer'));
    await tester.pump();
    expect(asked, 1);
    expect(find.text('Être prévenu de mon tour'), findsNothing);
    expect(find.textContaining('Vous serez prévenu'), findsOneWidget);
  });

  testWidgets('demande annulée par le médecin', (tester) async {
    repo.statuses = [fakeStatus(statut: TeledocRequestStatus.annulee)];
    await openQueue(tester);
    expect(find.text('Demande annulée'), findsOneWidget);
    expect(find.textContaining('remboursé'), findsOneWidget);
  });

  testWidgets('parcours : nouvelle demande → file d\'attente', (tester) async {
    repo.statuses = [fakeStatus(idDemande: 100, position: 2, wait: 15)];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: TeledocHomeScreen(
          session: teledocSession(UserRole.client),
          repository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nouvelle demande'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Motif'),
      'Migraine',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Description des symptômes'),
      'Mal de tête intense depuis ce matin',
    );
    final submit = find.text('Payer et envoyer la demande');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    // The queue screen polls forever: pump a few frames, not pumpAndSettle.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('File d\'attente'), findsOneWidget);
    expect(find.text('2e'), findsOneWidget);
  });
}
