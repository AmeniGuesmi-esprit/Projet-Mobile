import 'package:proxilife_shared/proxilife_shared.dart';

/// Something the patient should be told while waiting.
enum TeledocQueueEvent {
  /// Position ≤ [TeledocQueue.soonThreshold] : « C'est bientôt votre tour ».
  soon,

  /// A doctor started the consultation.
  started,

  /// The request was cancelled (e.g. by the doctor, patient absent).
  cancelled,
}

/// Turns successive queue statuses into events, each at most once
/// (pure logic, unit-tested).
///
/// - `soon` fires the first time the position reaches the threshold, and not
///   again if an urgent request pushes the patient back then forward
///   (no notification spam).
/// - `started` / `cancelled` fire on a status *change* only: opening the
///   screen on an already started request shows it in the UI without a
///   redundant notification.
class TeledocQueueTracker {
  bool _soonSent = false;
  TeledocRequestStatus? _lastStatus;

  List<TeledocQueueEvent> update(TeledocQueueStatusDto status) {
    final events = <TeledocQueueEvent>[];
    final position = status.positionFile;
    if (!_soonSent &&
        status.statut == TeledocRequestStatus.enAttente &&
        position != null &&
        TeledocQueue.isSoon(position)) {
      _soonSent = true;
      events.add(TeledocQueueEvent.soon);
    }
    final previous = _lastStatus;
    if (previous != null && previous != status.statut) {
      switch (status.statut) {
        case TeledocRequestStatus.enCours:
          events.add(TeledocQueueEvent.started);
        case TeledocRequestStatus.annulee:
          events.add(TeledocQueueEvent.cancelled);
        case TeledocRequestStatus.enAttente:
        case TeledocRequestStatus.terminee:
          break;
      }
    }
    _lastStatus = status.statut;
    return events;
  }
}

/// French notification texts for [event].
({String title, String body}) teledocNotificationText(
  TeledocQueueEvent event,
  TeledocQueueStatusDto status,
) => switch (event) {
  TeledocQueueEvent.soon => (
    title: 'C\'est bientôt votre tour',
    body: status.positionFile == 1
        ? 'Vous êtes le prochain patient. Restez disponible.'
        : 'Plus que ${status.positionFile! - 1} patient avant vous. '
              'Restez disponible.',
  ),
  TeledocQueueEvent.started => (
    title: 'Le médecin vous attend',
    body: status.typeConsultation == TeledocConsultationType.audio
        ? 'Votre consultation audio commence. Ouvrez ProxiLife.'
        : 'Votre consultation vidéo commence. Ouvrez ProxiLife.',
  ),
  TeledocQueueEvent.cancelled => (
    title: 'Consultation annulée',
    body: 'Votre demande a été annulée et remboursée.',
  ),
};

/// Delivers queue events to the user (local notifications in the app,
/// a fake in tests).
abstract class TeledocQueueNotifier {
  Future<void> notify(TeledocQueueEvent event, TeledocQueueStatusDto status);
}
