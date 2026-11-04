import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxilife/core/api/api_client.dart';
import 'package:proxilife/core/theme/app_theme.dart';
import 'package:proxilife/features/teledoc/presentation/screens/doctor/teledoc_doctor_consultation_screen.dart';
import 'package:proxilife/features/teledoc/presentation/screens/teledoc_home_screen.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import 'teledoc_fakes.dart';

Widget wrap(Widget child) => MaterialApp(theme: AppTheme.light(), home: child);

Future<void> scrollAndTap(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(finder);
}

void main() {
  late FakeTeledocRepository repo;

  setUp(() => repo = FakeTeledocRepository());

  Future<void> openDoctorHome(WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(
        TeledocHomeScreen(
          session: teledocSession(UserRole.medecin),
          repository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Espace médecin : file', () {
    testWidgets('file triée affichée, démarrage en vidéo', (tester) async {
      repo.queue = [
        fakeRequest(
          id: 1,
          motif: 'Éruption',
          urgence: TeledocUrgency.elevee,
          position: 1,
          wait: 0,
          aPhoto: true,
        ),
        fakeRequest(id: 2, motif: 'Toux', position: 2, wait: 15),
      ];
      await openDoctorHome(tester);
      expect(find.text('2 patients en attente'), findsOneWidget);
      expect(find.text('Éruption'), findsOneWidget);
      expect(find.text('Urgence élevée'), findsOneWidget);
      expect(find.byIcon(Icons.photo_outlined), findsOneWidget);

      await tester.tap(find.text('Démarrer la prochaine consultation'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vidéo'));
      await tester.pumpAndSettle();

      expect(repo.calls, contains('startNextConsultation'));
      expect(repo.lastPayload, {'type': TeledocConsultationType.video});
      expect(find.text('Consultation en cours'), findsOneWidget);
      expect(find.text('Terminer et envoyer l\'ordonnance'), findsOneWidget);
    });

    testWidgets('file vide : bouton désactivé', (tester) async {
      await openDoctorHome(tester);
      expect(find.text('La file est vide'), findsOneWidget);
      final button = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Démarrer la prochaine consultation'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('consultation déjà ouverte : reprise au lieu de démarrer', (
      tester,
    ) async {
      repo.queue = [fakeRequest(id: 2)];
      repo.consultationList = [fakeConsultation(id: 50)];
      await openDoctorHome(tester);
      expect(find.text('Consultation en cours'), findsOneWidget);
      expect(find.text('Démarrer la prochaine consultation'), findsNothing);
    });

    testWidgets('un confrère a été plus rapide : message et actualisation', (
      tester,
    ) async {
      repo.queue = [fakeRequest(id: 1)];
      await openDoctorHome(tester);
      await tester.tap(find.text('Démarrer la prochaine consultation'));
      await tester.pumpAndSettle();
      repo.nextError = const ApiException(
        409,
        'Cette demande vient d\'être prise en charge, réessayez',
      );
      await tester.tap(find.text('Audio'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('vient d\'être prise en charge'),
        findsOneWidget,
      );
      expect(repo.calls.where((c) => c == 'waitingQueue'), hasLength(2));
    });

    testWidgets('aperçu d\'une demande (lecture seule)', (tester) async {
      repo.queue = [
        fakeRequest(id: 3, description: 'Douleur au genou après une chute'),
      ];
      await openDoctorHome(tester);
      await tester.tap(find.text('Fièvre'));
      await tester.pumpAndSettle();
      expect(find.text('Douleur au genou après une chute'), findsOneWidget);
      expect(find.textContaining('ordre de la file'), findsOneWidget);
    });

    testWidgets('historique', (tester) async {
      repo.consultationList = [
        fakeConsultation(id: 9, ended: true, ordonnance: 'Repos'),
      ];
      await openDoctorHome(tester);
      await tester.tap(find.text('Historique'));
      await tester.pumpAndSettle();
      expect(find.text('Ameni Guesmi · Fièvre'), findsOneWidget);
      expect(find.text('Terminée'), findsOneWidget);
    });
  });

  group('Consultation (médecin)', () {
    Future<void> openConsultation(
      WidgetTester tester,
      TeledocConsultationDto c,
    ) async {
      repo
        ..consultationList = [c]
        ..requests = [
          fakeRequest(
            id: c.idDemande,
            statut: c.statutDemande,
            description: 'Fièvre à 39 °C depuis hier soir',
          ),
        ];
      await tester.pumpWidget(
        wrap(
          TeledocDoctorConsultationScreen(
            repository: repo,
            consultationId: c.id,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('ordonnance obligatoire pour terminer', (tester) async {
      await openConsultation(tester, fakeConsultation(id: 50));
      expect(find.text('Fièvre à 39 °C depuis hier soir'), findsOneWidget);

      await scrollAndTap(
        tester,
        find.text('Terminer et envoyer l\'ordonnance'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ordonnance obligatoire'), findsOneWidget);
      expect(repo.calls.where((c) => c.startsWith('end')), isEmpty);

      await tester.enterText(
        find.byType(TextFormField),
        'Paracétamol 1 g, 3 fois par jour pendant 5 jours',
      );
      await scrollAndTap(
        tester,
        find.text('Terminer et envoyer l\'ordonnance'),
      );
      await tester.pumpAndSettle();
      expect(repo.calls, contains('endConsultation 50'));
      expect(repo.lastPayload, {
        'ordonnance': 'Paracétamol 1 g, 3 fois par jour pendant 5 jours',
      });
      expect(find.text('Terminer et envoyer l\'ordonnance'), findsNothing);
      expect(find.text('Corriger'), findsOneWidget);
    });

    testWidgets('patient absent : annulation confirmée', (tester) async {
      await openConsultation(tester, fakeConsultation(id: 50, idDemande: 4));
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Patient absent (annuler)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('remboursé'), findsOneWidget);
      await tester.tap(find.text('Annuler la demande'));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('cancelRequest 4'));
    });

    testWidgets('remettre en file : suppression de la consultation', (
      tester,
    ) async {
      await openConsultation(tester, fakeConsultation(id: 50));
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remettre en file'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Remettre en file'));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('deleteConsultation 50'));
    });

    testWidgets('passer en audio pendant la consultation', (tester) async {
      await openConsultation(tester, fakeConsultation(id: 50));
      await tester.tap(find.text('Passer en audio'));
      await tester.pumpAndSettle();
      expect(repo.lastPayload, {
        'type': TeledocConsultationType.audio,
        'ordonnance': null,
      });
      expect(repo.calls, contains('updateConsultation 50'));
      expect(find.text('Passer en vidéo'), findsOneWidget);
    });

    testWidgets('terminée : correction possible, pas de suppression', (
      tester,
    ) async {
      await openConsultation(
        tester,
        fakeConsultation(id: 9, ended: true, ordonnance: 'Repos'),
      );
      expect(find.byIcon(Icons.more_vert), findsNothing);
      expect(find.textContaining('ne peut pas être supprimée'), findsOneWidget);

      await tester.tap(find.text('Corriger'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Repos 72 h');
      await scrollAndTap(tester, find.text('Enregistrer la correction'));
      await tester.pumpAndSettle();
      expect(repo.calls, contains('updateConsultation 9'));
      expect(find.text('Repos 72 h'), findsOneWidget);
    });
  });
}
