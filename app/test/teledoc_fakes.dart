import 'package:proxilife/core/api/api_client.dart';
import 'package:proxilife/core/session/session_controller.dart';
import 'package:proxilife/features/teledoc/domain/teledoc_call.dart';
import 'package:proxilife/features/teledoc/domain/teledoc_queue_tracker.dart';
import 'package:proxilife/features/teledoc/domain/teledoc_repository.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import 'fakes.dart';

/// A room in the server format (TeledocCallRoom).
const String fakeRoom = 'ProxiLifeTeleDoc0123456789abcdef0123456789abcdef';

TeledocRequestDto fakeRequest({
  int id = 1,
  String motif = 'Fièvre',
  String description = 'Fièvre à 39 °C depuis hier soir',
  TeledocUrgency urgence = TeledocUrgency.moyenne,
  TeledocRequestStatus statut = TeledocRequestStatus.enAttente,
  int? position = 2,
  int? wait = 15,
  bool aPhoto = false,
  int? consultationId,
  String patientNom = 'Ameni Guesmi',
}) => TeledocRequestDto(
  id: id,
  motif: motif,
  description: description,
  urgence: urgence,
  aPhoto: aPhoto,
  statut: statut,
  positionFile: statut == TeledocRequestStatus.enAttente ? position : null,
  tempsEstimeMinutes: statut == TeledocRequestStatus.enAttente ? wait : null,
  patientNom: patientNom,
  transactionId: -id,
  consultationId: consultationId,
  creeLe: '2026-10-14T09:00:00.000',
  modifieLe: '2026-10-14T09:00:00.000',
);

TeledocConsultationDto fakeConsultation({
  int id = 7,
  int idDemande = 1,
  bool ended = false,
  String? ordonnance,
  TeledocConsultationType type = TeledocConsultationType.video,
  TeledocRequestStatus? statutDemande,
  String? pharmacieNom,
  String? salleAppel = fakeRoom,
}) => TeledocConsultationDto(
  id: id,
  dateDebut: '2026-10-14T09:30:00.000',
  dateFin: ended ? '2026-10-14T09:48:00.000' : null,
  type: type,
  ordonnance: ordonnance,
  idPharmacie: pharmacieNom == null ? null : 1,
  pharmacieNom: pharmacieNom,
  idDemande: idDemande,
  idMedecin: 10,
  medecinNom: 'Sami Ben Salah',
  patientNom: 'Ameni Guesmi',
  motif: 'Fièvre',
  urgence: TeledocUrgency.moyenne,
  statutDemande:
      statutDemande ??
      (ended ? TeledocRequestStatus.terminee : TeledocRequestStatus.enCours),
  salleAppel: ended ? null : salleAppel,
);

TeledocQueueStatusDto fakeStatus({
  int idDemande = 1,
  TeledocRequestStatus statut = TeledocRequestStatus.enAttente,
  int? position = 3,
  int? wait = 30,
  int? consultationId,
  TeledocConsultationType? type,
  String? salleAppel = fakeRoom,
}) => TeledocQueueStatusDto(
  idDemande: idDemande,
  statut: statut,
  positionFile: statut == TeledocRequestStatus.enAttente ? position : null,
  tempsEstimeMinutes: statut == TeledocRequestStatus.enAttente ? wait : null,
  taille: 4,
  consultationId: consultationId,
  typeConsultation: type,
  salleAppel: statut == TeledocRequestStatus.enCours ? salleAppel : null,
);

/// In-memory [TeledocRepository] recording calls. Set [nextError] to make
/// the next call fail with an [ApiException].
class FakeTeledocRepository implements TeledocRepository {
  List<TeledocRequestDto> requests = [];
  List<TeledocRequestDto> queue = [];
  List<TeledocConsultationDto> consultationList = [];
  List<TeledocPharmacyDto> pharmacies = [];

  /// Successive answers of [queueStatus]; the last one is repeated.
  List<TeledocQueueStatusDto> statuses = [];
  int queueStatusCalls = 0;

  ApiException? nextError;
  final List<String> calls = [];

  /// Payload of the last call that had one.
  Map<String, Object?>? lastPayload;

  void _record(String call, [Map<String, Object?>? payload]) {
    calls.add(call);
    // Reloads after an action (no payload) must not hide the action's data.
    if (payload != null) lastPayload = payload;
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
  }

  @override
  Future<List<TeledocRequestDto>> myRequests({
    TeledocRequestStatus? statut,
  }) async {
    _record('myRequests');
    return requests;
  }

  @override
  Future<TeledocRequestDto> request(int id) async {
    _record('request $id');
    return [...requests, ...queue].firstWhere((r) => r.id == id);
  }

  @override
  Future<TeledocRequestDto> createRequest({
    required String motif,
    required String description,
    required TeledocUrgency urgence,
    List<int>? photoBytes,
  }) async {
    _record('createRequest', {
      'motif': motif,
      'description': description,
      'urgence': urgence,
      'photo': photoBytes?.length,
    });
    final created = fakeRequest(
      id: 100,
      motif: motif,
      description: description,
      urgence: urgence,
      aPhoto: photoBytes != null,
    );
    requests = [created, ...requests];
    return created;
  }

  @override
  Future<TeledocRequestDto> updateRequest(
    int id, {
    String? motif,
    String? description,
    TeledocUrgency? urgence,
    List<int>? photoBytes,
    bool removePhoto = false,
  }) async {
    _record('updateRequest $id', {
      'motif': motif,
      'description': description,
      'urgence': urgence,
      'photo': photoBytes?.length,
      'removePhoto': removePhoto,
    });
    final old = requests.firstWhere((r) => r.id == id);
    final updated = fakeRequest(
      id: id,
      motif: motif ?? old.motif,
      description: description ?? old.description,
      urgence: urgence ?? old.urgence,
      aPhoto: removePhoto ? false : (photoBytes != null || old.aPhoto),
    );
    requests = [for (final r in requests) r.id == id ? updated : r];
    return updated;
  }

  @override
  Future<TeledocRequestDto> cancelRequest(int id) async {
    _record('cancelRequest $id');
    final cancelled = fakeRequest(id: id, statut: TeledocRequestStatus.annulee);
    requests = [for (final r in requests) r.id == id ? cancelled : r];
    return cancelled;
  }

  @override
  Future<TeledocQueueStatusDto> queueStatus(int id) async {
    _record('queueStatus $id');
    final index = queueStatusCalls < statuses.length
        ? queueStatusCalls
        : statuses.length - 1;
    queueStatusCalls++;
    return statuses[index];
  }

  @override
  TeledocPhotoSource photoOf(TeledocRequestDto request) =>
      TeledocPhotoSource('http://127.0.0.1:1/photo/${request.id}', const {});

  @override
  Future<List<TeledocRequestDto>> waitingQueue() async {
    _record('waitingQueue');
    return queue;
  }

  @override
  Future<TeledocConsultationDto> startNextConsultation(
    TeledocConsultationType type,
  ) async {
    _record('startNextConsultation', {'type': type});
    final head = queue.first;
    queue = queue.skip(1).toList();
    final started = fakeConsultation(id: 50, idDemande: head.id, type: type);
    consultationList = [started, ...consultationList];
    requests = [
      ...requests,
      fakeRequest(
        id: head.id,
        statut: TeledocRequestStatus.enCours,
        consultationId: 50,
      ),
    ];
    return started;
  }

  @override
  Future<List<TeledocConsultationDto>> consultations() async {
    _record('consultations');
    return consultationList;
  }

  @override
  Future<TeledocConsultationDto> consultation(int id) async {
    _record('consultation $id');
    return consultationList.firstWhere((c) => c.id == id);
  }

  @override
  Future<TeledocConsultationDto> updateConsultation(
    int id, {
    TeledocConsultationType? type,
    String? ordonnance,
  }) async {
    _record('updateConsultation $id', {'type': type, 'ordonnance': ordonnance});
    final old = consultationList.firstWhere((c) => c.id == id);
    final updated = fakeConsultation(
      id: id,
      idDemande: old.idDemande,
      ended: old.estTerminee,
      type: type ?? old.type,
      ordonnance: ordonnance ?? old.ordonnance,
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<TeledocConsultationDto> endConsultation(
    int id,
    String ordonnance,
  ) async {
    _record('endConsultation $id', {'ordonnance': ordonnance});
    final old = consultationList.firstWhere((c) => c.id == id);
    final ended = fakeConsultation(
      id: id,
      idDemande: old.idDemande,
      ended: true,
      ordonnance: ordonnance,
    );
    _replace(ended);
    return ended;
  }

  @override
  Future<void> deleteConsultation(int id) async {
    _record('deleteConsultation $id');
    consultationList = consultationList.where((c) => c.id != id).toList();
  }

  @override
  Future<TeledocConsultationDto> choosePharmacy(
    int consultationId,
    int pharmacyId,
  ) async {
    _record('choosePharmacy $consultationId $pharmacyId');
    final old = consultationList.firstWhere((c) => c.id == consultationId);
    final updated = fakeConsultation(
      id: consultationId,
      idDemande: old.idDemande,
      ended: true,
      ordonnance: old.ordonnance,
      pharmacieNom: pharmacies.firstWhere((p) => p.id == pharmacyId).nom,
    );
    _replace(updated);
    return updated;
  }

  @override
  Future<List<TeledocPharmacyDto>> nearestPharmacies({
    required double lat,
    required double lng,
    int limit = 10,
  }) async {
    _record('nearestPharmacies', {'lat': lat, 'lng': lng});
    return pharmacies;
  }

  void _replace(TeledocConsultationDto c) => consultationList = [
    for (final x in consultationList) x.id == c.id ? c : x,
  ];
}

/// Records the links the app tries to open; [succeeds] simulates a device
/// without any app able to open them.
class RecordingLinkOpener implements TeledocLinkOpener {
  final List<Uri> opened = [];
  bool succeeds = true;

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return succeeds;
  }
}

class RecordingNotifier implements TeledocQueueNotifier {
  final List<TeledocQueueEvent> events = [];

  @override
  Future<void> notify(
    TeledocQueueEvent event,
    TeledocQueueStatusDto status,
  ) async {
    events.add(event);
  }
}

/// Test session already logged in with [role].
SessionController teledocSession(UserRole role) =>
    makeTestSession()
      ..user = UserDto(
        id: role == UserRole.medecin ? 10 : 1,
        nom: role == UserRole.medecin ? 'Ben Salah' : 'Guesmi',
        prenom: role == UserRole.medecin ? 'Sami' : 'Ameni',
        email: 'test@proxilife.fr',
        telephone: '98000000',
        role: role,
        statutCompte: AccountStatus.actif,
        soldeCentimes: 5000,
      );
