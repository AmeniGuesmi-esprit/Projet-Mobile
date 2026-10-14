import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxilife/core/api/api_client.dart';
import 'package:proxilife/core/theme/app_theme.dart';
import 'package:proxilife/features/teledoc/presentation/screens/patient/teledoc_consultation_detail_screen.dart';
import 'package:proxilife/features/teledoc/presentation/screens/patient/teledoc_request_detail_screen.dart';
import 'package:proxilife/features/teledoc/presentation/screens/patient/teledoc_request_form_screen.dart';
import 'package:proxilife/features/teledoc/presentation/screens/teledoc_home_screen.dart';
import 'package:proxilife/features/teledoc/presentation/widgets/teledoc_entry_card.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import 'teledoc_fakes.dart';

/// A real 1×1 PNG (Image.memory must be able to decode it).
final Uint8List tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// Scrolls the lazy list until [finder] is built and visible, then taps it.
Future<void> scrollAndTap(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(finder);
}

Widget wrap(Widget child) => MaterialApp(theme: AppTheme.light(), home: child);

void main() {
  group('Point d\'entrée sur l\'accueil', () {
    testWidgets('visible pour un patient avec le badge TeleDoc', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: TeledocEntryCard(session: teledocSession(UserRole.client)),
          ),
        ),
      );
      expect(find.text('TeleDoc Express'), findsOneWidget);
      expect(find.text('Consulter un médecin à distance'), findsOneWidget);
    });

    testWidgets('libellé médecin', (tester) async {
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: TeledocEntryCard(session: teledocSession(UserRole.medecin)),
          ),
        ),
      );
      expect(find.text('Votre file de patients'), findsOneWidget);
    });

    testWidgets('masqué pour les autres rôles', (tester) async {
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: TeledocEntryCard(
              session: teledocSession(UserRole.conducteur),
            ),
          ),
        ),
      );
      expect(find.text('TeleDoc Express'), findsNothing);
    });
  });

  group('Espace patient', () {
    testWidgets('sans demande active : bouton « Nouvelle demande »', (
      tester,
    ) async {
      final repo = FakeTeledocRepository()
        ..requests = [
          fakeRequest(
            id: 3,
            motif: 'Angine',
            statut: TeledocRequestStatus.terminee,
          ),
        ];
      await tester.pumpWidget(
        wrap(
          TeledocHomeScreen(
            session: teledocSession(UserRole.client),
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nouvelle demande'), findsOneWidget);
      expect(find.text('Angine'), findsOneWidget);
      expect(find.text('Terminée'), findsOneWidget);
    });

    testWidgets('demande active : position et attente affichées', (
      tester,
    ) async {
      final repo = FakeTeledocRepository()
        ..requests = [fakeRequest(position: 2, wait: 15)];
      await tester.pumpWidget(
        wrap(
          TeledocHomeScreen(
            session: teledocSession(UserRole.client),
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Demande en cours'), findsOneWidget);
      expect(find.textContaining('2e dans la file'), findsOneWidget);
      expect(find.textContaining('Environ 15 min'), findsOneWidget);
      expect(
        find.text('Nouvelle demande'),
        findsNothing,
        reason: 'une seule demande active',
      );
    });

    testWidgets('erreur serveur : message et « Réessayer »', (tester) async {
      final repo = FakeTeledocRepository()
        ..nextError = const ApiException(0, 'Serveur local indisponible');
      await tester.pumpWidget(
        wrap(
          TeledocHomeScreen(
            session: teledocSession(UserRole.client),
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Serveur local indisponible'), findsOneWidget);
      await tester.tap(find.text('Réessayer').first);
      await tester.pumpAndSettle();
      expect(find.text('Nouvelle demande'), findsOneWidget);
    });

    testWidgets('rôle non autorisé : message explicite', (tester) async {
      await tester.pumpWidget(
        wrap(
          TeledocHomeScreen(
            session: teledocSession(UserRole.commercant),
            repository: FakeTeledocRepository(),
          ),
        ),
      );
      expect(find.text('Réservé aux patients et aux médecins'), findsOneWidget);
    });
  });

  group('Formulaire de demande', () {
    Future<FakeTeledocRepository> openForm(
      WidgetTester tester, {
      TeledocImagePicker? picker,
      TeledocRequestDto? initial,
    }) async {
      final repo = FakeTeledocRepository();
      if (initial != null) repo.requests = [initial];
      await tester.pumpWidget(
        wrap(
          TeledocRequestFormScreen(
            session: teledocSession(UserRole.client),
            repository: repo,
            initial: initial,
            pickImage: picker ?? (_) async => null,
          ),
        ),
      );
      return repo;
    }

    Finder submitButton() =>
        find.widgetWithText(FilledButton, 'Payer et envoyer la demande');

    testWidgets('validation : messages français, aucun envoi', (tester) async {
      final repo = await openForm(tester);
      await scrollAndTap(tester, submitButton());
      await tester.pump();
      expect(find.text('Motif obligatoire'), findsOneWidget);
      expect(find.text('Description obligatoire'), findsOneWidget);
      expect(repo.calls, isEmpty);
    });

    testWidgets('tarif affiché (30 DT)', (tester) async {
      await openForm(tester);
      expect(find.textContaining('30'), findsWidgets);
      expect(find.text('Tarif de la téléconsultation'), findsOneWidget);
    });

    testWidgets('création avec photo et urgence élevée', (tester) async {
      final photo = tinyPng;
      final repo = await openForm(tester, picker: (_) async => photo);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motif'),
        'Éruption',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description des symptômes'),
        'Plaques rouges sur le bras depuis ce matin',
      );
      await tester.tap(find.text('Élevée'));
      await scrollAndTap(tester, find.text('Ajouter une photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prendre une photo'));
      await tester.pumpAndSettle();
      expect(find.text('Changer'), findsOneWidget);

      await scrollAndTap(tester, submitButton());
      await tester.pumpAndSettle();
      expect(repo.calls, ['createRequest']);
      expect(repo.lastPayload, {
        'motif': 'Éruption',
        'description': 'Plaques rouges sur le bras depuis ce matin',
        'urgence': TeledocUrgency.elevee,
        'photo': tinyPng.length,
      });
    });

    testWidgets('photo de plus de 2 Mo refusée côté app', (tester) async {
      final big = Uint8List(TeledocPhotoRules.maxBytes + 1);
      await openForm(tester, picker: (_) async => big);
      await scrollAndTap(tester, find.text('Ajouter une photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choisir dans la galerie'));
      await tester.pumpAndSettle();
      expect(
        find.text('Photo trop volumineuse : 2 Mo maximum'),
        findsOneWidget,
      );
      expect(find.text('Changer'), findsNothing);
    });

    testWidgets('erreur serveur : saisie conservée, snackbar', (tester) async {
      final repo = await openForm(tester);
      repo.nextError = const ApiException(
        409,
        'Vous avez déjà une demande en cours',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Motif'),
        'Toux',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description des symptômes'),
        'Toux sèche depuis trois jours',
      );
      await scrollAndTap(tester, submitButton());
      await tester.pumpAndSettle();
      expect(find.text('Vous avez déjà une demande en cours'), findsOneWidget);
      expect(find.text('Toux'), findsOneWidget);
    });

    testWidgets('modification sans changement : aucun appel', (tester) async {
      final repo = await openForm(tester, initial: fakeRequest(id: 4));
      await scrollAndTap(tester, find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(repo.calls, isEmpty);
    });
  });

  group('Détail d\'une demande', () {
    Future<FakeTeledocRepository> openDetail(
      WidgetTester tester,
      TeledocRequestDto request,
    ) async {
      final repo = FakeTeledocRepository()..requests = [request];
      await tester.pumpWidget(
        wrap(
          TeledocRequestDetailScreen(
            session: teledocSession(UserRole.client),
            repository: repo,
            requestId: request.id,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('annulation avec confirmation et remboursement annoncé', (
      tester,
    ) async {
      final repo = await openDetail(tester, fakeRequest(id: 5));
      await tester.scrollUntilVisible(
        find.text('Modifier'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Suivre la file en direct'), findsOneWidget);
      expect(find.text('Modifier'), findsOneWidget);
      await scrollAndTap(tester, find.text('Annuler la demande'));
      await tester.pumpAndSettle();
      expect(find.textContaining('remboursés'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Annuler la demande'),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.calls, contains('cancelRequest 5'));
      expect(find.text('Annulée'), findsOneWidget);
      expect(find.text('Modifier'), findsNothing);
    });

    testWidgets('« Garder ma place » ne fait rien', (tester) async {
      final repo = await openDetail(tester, fakeRequest(id: 5));
      await scrollAndTap(tester, find.text('Annuler la demande'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Garder ma place'));
      await tester.pumpAndSettle();
      expect(repo.calls.where((c) => c.startsWith('cancel')), isEmpty);
    });

    testWidgets('en consultation : ni modification ni annulation', (
      tester,
    ) async {
      await openDetail(
        tester,
        fakeRequest(id: 6, statut: TeledocRequestStatus.enCours),
      );
      expect(find.text('Consultation en cours'), findsOneWidget);
      expect(find.text('Modifier'), findsNothing);
      expect(find.text('Annuler la demande'), findsNothing);
    });

    testWidgets('terminée : accès à l\'ordonnance', (tester) async {
      await openDetail(
        tester,
        fakeRequest(
          id: 7,
          statut: TeledocRequestStatus.terminee,
          consultationId: 9,
        ),
      );
      expect(find.text('Voir l\'ordonnance'), findsOneWidget);
    });
  });

  testWidgets('Consultation : ordonnance et pharmacie', (tester) async {
    final repo = FakeTeledocRepository()
      ..consultationList = [
        fakeConsultation(
          id: 9,
          ended: true,
          ordonnance: 'Paracétamol 1 g, 3 fois par jour',
          pharmacieNom: 'Pharmacie du Lac',
        ),
      ];
    await tester.pumpWidget(
      wrap(
        TeledocConsultationDetailScreen(repository: repo, consultationId: 9),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Paracétamol 1 g, 3 fois par jour'), findsOneWidget);
    expect(find.text('Dr Sami Ben Salah'), findsOneWidget);
    expect(find.text('18 min'), findsOneWidget);
    expect(find.text('Pharmacie du Lac'), findsOneWidget);
  });
}
