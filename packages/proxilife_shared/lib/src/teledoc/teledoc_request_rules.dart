import 'teledoc_enums.dart';

/// Canonical state machine of a TeleDoc request. The server is authoritative;
/// the app only uses it to show or hide actions. Never re-implement it.
///
/// ```
/// en_attente ──médecin──▶ en_cours ──médecin──▶ terminee
///     │                     │  │
///  patient               médecin└──médecin──▶ en_attente (consultation supprimée)
///     ▼                     ▼
///  annulee ◀────────────────┘
/// ```
class TeledocRequestRules {
  const TeledocRequestRules._();

  static const Map<TeledocRequestStatus,
      Map<TeledocRequestStatus, TeledocActor>> _allowed = {
    TeledocRequestStatus.enAttente: {
      TeledocRequestStatus.enCours: TeledocActor.medecin,
      TeledocRequestStatus.annulee: TeledocActor.patient,
    },
    TeledocRequestStatus.enCours: {
      TeledocRequestStatus.terminee: TeledocActor.medecin,
      // Patient absent: the doctor in charge cancels.
      TeledocRequestStatus.annulee: TeledocActor.medecin,
      // Consultation deleted (taken by mistake): back in the queue.
      TeledocRequestStatus.enAttente: TeledocActor.medecin,
    },
    TeledocRequestStatus.terminee: {},
    TeledocRequestStatus.annulee: {},
  };

  static bool canTransition(
    TeledocRequestStatus from,
    TeledocRequestStatus to,
    TeledocActor actor,
  ) =>
      _allowed[from]?[to] == actor;

  /// Motif, description, urgency and photo can only change while waiting.
  static bool canEdit(TeledocRequestStatus status) =>
      status == TeledocRequestStatus.enAttente;

  /// A request counts as "active" (one at a time per patient) until it ends.
  static bool isActive(TeledocRequestStatus status) =>
      status == TeledocRequestStatus.enAttente ||
      status == TeledocRequestStatus.enCours;

  static bool isTerminal(TeledocRequestStatus status) =>
      _allowed[status]!.isEmpty;
}
