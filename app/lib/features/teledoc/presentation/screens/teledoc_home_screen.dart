import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../data/teledoc_api_repository.dart';
import '../../domain/teledoc_repository.dart';
import 'doctor/teledoc_doctor_home_screen.dart';
import 'patient/teledoc_patient_home_screen.dart';

/// Entry of the TeleDoc module: routes to the patient or the doctor space
/// according to the connected user's role.
class TeledocHomeScreen extends StatelessWidget {
  const TeledocHomeScreen({super.key, required this.session, this.repository});

  final SessionController session;

  /// Injected in tests; defaults to the HTTP implementation.
  final TeledocRepository? repository;

  @override
  Widget build(BuildContext context) {
    final repo = repository ?? TeledocApiRepository(session.api);
    return switch (session.user?.role) {
      UserRole.client => TeledocPatientHomeScreen(
        session: session,
        repository: repo,
      ),
      UserRole.medecin => TeledocDoctorHomeScreen(repository: repo),
      _ => Scaffold(
        appBar: AppBar(title: const Text('TeleDoc Express')),
        body: const EmptyState(
          icon: Icons.medical_services_outlined,
          title: 'Réservé aux patients et aux médecins',
          message:
              'Connectez-vous avec un compte client ou médecin pour '
              'utiliser la téléconsultation.',
          color: AppColors.moduleTeleDoc,
        ),
      ),
    };
  }
}
