import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxilife/core/theme/app_theme.dart';
import 'package:proxilife/features/teledoc/domain/teledoc_call.dart';
import 'package:proxilife/features/teledoc/presentation/screens/doctor/teledoc_doctor_consultation_screen.dart';
import 'package:proxilife/features/teledoc/presentation/screens/patient/teledoc_queue_screen.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import 'teledoc_fakes.dart';

Widget wrap(Widget child) => MaterialApp(theme: AppTheme.light(), home: child);

void main() {
  group('TeledocCallLink (Jitsi)', () {
    test('vidéo : salle + options Jitsi + nom affiché', () {
      final uri = TeledocCallLink.build(
        room: fakeRoom,
        type: TeledocConsultationType.video,
        displayName: 'Dr Sami Ben Salah',
        baseUrl: 'https://meet.jit.si',
      )!;
      expect(uri.toString(), startsWith('https://meet.jit.si/$fakeRoom#'));
      expect(uri.fragment, contains('config.prejoinConfig.enabled=true'));
      expect(uri.fragment, isNot(contains('startWithVideoMuted')));
      expect(
        Uri.decodeComponent(uri.fragment),
        contains('userInfo.displayName="Dr Sami Ben Salah"'),
      );
    });

    test('audio : la caméra démarre coupée', () {
      final uri = TeledocCallLink.build(
        room: fakeRoom,
        type: TeledocConsultationType.audio,
      )!;
      expect(uri.fragment, contains('config.startWithVideoMuted=true'));
    });

    test('instance auto-hébergée avec sous-chemin', () {
      final uri = TeledocCallLink.build(
        room: fakeRoom,
        type: TeledocConsultationType.video,
        baseUrl: 'https://visio.example.tn/jitsi/',
      )!;
      expect(uri.path, '/jitsi/$fakeRoom');
    });

    test('refuse une salle invalide ou une URL non HTTPS', () {
      expect(
        TeledocCallLink.build(
          room: 'x/../../evil',
          type: TeledocConsultationType.video,
        ),
        isNull,
      );
      expect(
        TeledocCallLink.build(room: null, type: TeledocConsultationType.video),
        isNull,
      );
      expect(
        TeledocCallLink.build(
          room: fakeRoom,
          type: TeledocConsultationType.video,
          baseUrl: 'http://meet.jit.si',
        ),
        isNull,
      );
    });
  });

  group("Médecin : rejoindre l'appel", () {
    late FakeTeledocRepository repo;
    late RecordingLinkOpener opener;

    setUp(() {
      repo = FakeTeledocRepository();
      opener = RecordingLinkOpener();
    });

    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          TeledocDoctorConsultationScreen(
            repository: repo,
            consultationId: 7,
            linkOpener: opener,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('ouvre Jitsi avec la salle et le nom du médecin', (
      tester,
    ) async {
      repo.consultationList = [fakeConsultation()];
      repo.requests = [fakeRequest(statut: TeledocRequestStatus.enCours)];
      await open(tester);

      expect(find.text('Appel vidéo'), findsOneWidget);
      expect(find.textContaining('connectez-vous une fois'), findsOneWidget);
      await tester.tap(find.text("Rejoindre l'appel vidéo"));
      await tester.pumpAndSettle();
      expect(opener.opened, hasLength(1));
      expect(opener.opened.single.path, '/$fakeRoom');
      expect(
        Uri.decodeComponent(opener.opened.single.fragment),
        contains('"Dr Sami Ben Salah"'),
      );
    });

    testWidgets('aucune app pour ouvrir le lien : message + copie', (
      tester,
    ) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      opener.succeeds = false;
      repo.consultationList = [
        fakeConsultation(type: TeledocConsultationType.audio),
      ];
      repo.requests = [fakeRequest(statut: TeledocRequestStatus.enCours)];
      await open(tester);

      await tester.tap(find.text("Rejoindre l'appel audio"));
      await tester.pumpAndSettle();
      expect(
        find.text("Impossible d'ouvrir l'appel sur cet appareil"),
        findsOneWidget,
      );
      await tester.tap(find.text('Copier le lien').last);
      await tester.pumpAndSettle();
      expect(copied.single, contains(fakeRoom));
    });

    testWidgets("consultation terminée : plus de bouton d'appel", (
      tester,
    ) async {
      repo.consultationList = [
        fakeConsultation(ended: true, ordonnance: 'Paracétamol 1 g'),
      ];
      repo.requests = [fakeRequest(statut: TeledocRequestStatus.terminee)];
      await open(tester);
      expect(find.text("Rejoindre l'appel vidéo"), findsNothing);
      expect(find.text('Durée'), findsOneWidget);
    });
  });

  testWidgets("patient : le polling apporte la salle, le bouton ouvre Jitsi", (
    tester,
  ) async {
    final repo = FakeTeledocRepository()
      ..statuses = [
        fakeStatus(
          statut: TeledocRequestStatus.enCours,
          consultationId: 7,
          type: TeledocConsultationType.video,
        ),
      ];
    final opener = RecordingLinkOpener();
    await tester.pumpWidget(
      wrap(
        TeledocQueueScreen(
          session: teledocSession(UserRole.client),
          repository: repo,
          requestId: 1,
          notifier: RecordingNotifier(),
          linkOpener: opener,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Le médecin vous attend'), findsOneWidget);
    final join = find.text("Rejoindre l'appel vidéo");
    await tester.scrollUntilVisible(
      join,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(join);
    await tester.pump();
    expect(opener.opened.single.path, '/$fakeRoom');
    expect(
      Uri.decodeComponent(opener.opened.single.fragment),
      contains('"Ameni Guesmi"'),
    );
    // Dispose the screen so the polling timer stops before the test ends.
    await tester.pumpWidget(const SizedBox());
  });
}
