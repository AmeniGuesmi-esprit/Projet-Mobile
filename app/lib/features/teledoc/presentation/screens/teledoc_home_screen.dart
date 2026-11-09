import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../data/sqflite_teledoc_history_store.dart';
import '../../data/teledoc_api_repository.dart';
import '../../data/teledoc_offline_repository.dart';
import '../../domain/teledoc_repository.dart';
import 'doctor/teledoc_doctor_home_screen.dart';
import 'patient/teledoc_patient_home_screen.dart';
import '../teledoc_theme.dart';

/// Entry of the TeleDoc module: doctors get their space; every other role
/// consults as a patient (like FoodSave's client side).
class TeledocHomeScreen extends StatelessWidget {
  const TeledocHomeScreen({super.key, required this.session, this.repository});

  final SessionController session;

  /// Injected in tests; defaults to the HTTP implementation.
  final TeledocRepository? repository;

  @override
  Widget build(BuildContext context) {
    final user = session.user;
    final repo = repository ??
        (user == null
            ? TeledocApiRepository(session.api)
            // Consultation history also kept on the phone (D45).
            : TeledocOfflineRepository(
                TeledocApiRepository(session.api),
                SqfliteTeledocHistoryStore.shared,
                user.id,
              ));
    return TeledocThemed(
      child: switch (session.user?.role) {
        UserRole.medecin => TeledocDoctorHomeScreen(repository: repo),
        null => Scaffold(
          appBar: AppBar(title: const Text('TeleDoc Express')),
          body: const EmptyState(
            icon: Icons.medical_services_outlined,
            title: 'Connexion requise',
            message: 'Connectez-vous pour utiliser la téléconsultation.',
            color: AppColors.moduleTeleDoc,
          ),
        ),
        _ => TeledocPatientHomeScreen(
          session: session,
          repository: repo,
        ),
      },
    );
  }
}
