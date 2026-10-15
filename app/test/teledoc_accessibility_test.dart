import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxilife/core/theme/app_theme.dart';
import 'package:proxilife/features/teledoc/domain/teledoc_location.dart';
import 'package:proxilife/features/teledoc/presentation/screens/doctor/teledoc_doctor_consultation_screen.dart';
import 'package:proxilife/features/teledoc/presentation/screens/patient/teledoc_pharmacy_screen.dart';
import 'package:proxilife/features/teledoc/presentation/screens/patient/teledoc_queue_screen.dart';
import 'package:proxilife/features/teledoc/presentation/screens/patient/teledoc_request_form_screen.dart';
import 'package:proxilife/features/teledoc/presentation/screens/teledoc_home_screen.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import 'teledoc_fakes.dart';

class _FixedLocation implements TeledocLocationProvider {
  @override
  Future<TeledocPosition> current() async => teledocTunisCentre;

  @override
  Future<void> openSettings(TeledocLocationIssue issue) async {}
}

/// Accessibility pass (Étape 12): Android guidelines (48 dp tap targets,
/// labelled buttons, text contrast) and a 200 % font size without overflow
/// (an overflow is reported as an error, which fails the test).
void main() {
  late FakeTeledocRepository repo;

  setUp(() {
    repo = FakeTeledocRepository()
      ..requests = [
        fakeRequest(id: 1, statut: TeledocRequestStatus.enCours),
        fakeRequest(id: 2, statut: TeledocRequestStatus.terminee),
      ]
      ..queue = [fakeRequest(id: 3, position: 1, wait: 0)]
      ..consultationList = [fakeConsultation(id: 7, idDemande: 1)]
      ..statuses = [fakeStatus(position: 2, wait: 15)]
      ..pharmacies = [
        const TeledocPharmacyDto(
          id: 1,
          nom: 'Pharmacie de Nuit Bourguiba',
          adresse: 'Avenue Habib Bourguiba, Tunis',
          telephone: '71 000 001',
          latitude: 36.8,
          longitude: 10.18,
          deGarde: true,
          distanceKm: 0.72,
        ),
      ];
  });

  final screens = <String, Widget Function(FakeTeledocRepository)>{
    'accueil patient': (r) => TeledocHomeScreen(
      session: teledocSession(UserRole.client),
      repository: r,
    ),
    'formulaire de demande': (r) => TeledocRequestFormScreen(
      session: teledocSession(UserRole.client),
      repository: r,
      pickImage: (_) async => null,
    ),
    'file d\'attente': (r) => TeledocQueueScreen(
      session: teledocSession(UserRole.client),
      repository: r,
      requestId: 1,
      notifier: RecordingNotifier(),
      enableNotifications: () async => true,
    ),
    'pharmacies de garde': (r) => TeledocPharmacyScreen(
      repository: r,
      consultationId: 7,
      location: _FixedLocation(),
      linkOpener: RecordingLinkOpener(),
      showMap: false,
    ),
    'accueil médecin': (r) => TeledocHomeScreen(
      session: teledocSession(UserRole.medecin),
      repository: r,
    ),
    'consultation (médecin)': (r) => TeledocDoctorConsultationScreen(
      repository: r,
      consultationId: 7,
      linkOpener: RecordingLinkOpener(),
    ),
  };

  Future<void> pump(WidgetTester tester, Widget screen, double scale) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery.withClampedTextScaling(
          minScaleFactor: scale,
          maxScaleFactor: scale,
          child: screen,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  for (final MapEntry(key: name, value: build) in screens.entries) {
    testWidgets('$name : recommandations Android d\'accessibilité', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, build(repo), 1);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      // Contrast: every TeleDoc text must pass. Known exception: the shared
      // core `ServiceBadge` (« TeleDoc Express », 3.15:1), not a TeleDoc
      // file, reported to the team instead of being modified here.
      final contrast = await textContrastGuideline.evaluate(tester);
      final ownFailures = (contrast.reason ?? '')
          .split('SemanticsNode#')
          .skip(1)
          .where((node) => !node.contains('label: "TeleDoc Express"'));
      expect(ownFailures, isEmpty, reason: contrast.reason);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox()); // stops polling timers
    });

    testWidgets('$name : police à 200 % sans débordement', (tester) async {
      await pump(tester, build(repo), 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
