import 'package:proxilife_shared/proxilife_shared.dart';

/// Everything needed to display an authenticated request photo with
/// `Image.network(url, headers: headers)`.
class TeledocPhotoSource {
  const TeledocPhotoSource(this.url, this.headers);

  final String url;
  final Map<String, String> headers;
}

/// TeleDoc data access, as seen by the presentation layer.
///
/// Entities are the shared DTOs from `proxilife_shared` (same classes as the
/// server: no duplicated model). The implementation lives in `data/`; tests
/// use a fake.
abstract class TeledocRepository {
  // ---- Patient : demandes ----
  Future<List<TeledocRequestDto>> myRequests({TeledocRequestStatus? statut});
  Future<TeledocRequestDto> request(int id);
  Future<TeledocRequestDto> createRequest({
    required String motif,
    required String description,
    required TeledocUrgency urgence,
    List<int>? photoBytes,
  });
  Future<TeledocRequestDto> updateRequest(
    int id, {
    String? motif,
    String? description,
    TeledocUrgency? urgence,
    List<int>? photoBytes,
    bool removePhoto = false,
  });

  /// Patient (waiting request) or doctor in charge (patient absent).
  Future<TeledocRequestDto> cancelRequest(int id);
  Future<TeledocQueueStatusDto> queueStatus(int id);
  TeledocPhotoSource photoOf(TeledocRequestDto request);

  // ---- Médecin : file et consultations ----
  Future<List<TeledocRequestDto>> waitingQueue();
  Future<TeledocConsultationDto> startNextConsultation(
    TeledocConsultationType type,
  );

  // ---- Consultations (patient et médecin) ----
  Future<List<TeledocConsultationDto>> consultations();
  Future<TeledocConsultationDto> consultation(int id);
  Future<TeledocConsultationDto> updateConsultation(
    int id, {
    TeledocConsultationType? type,
    String? ordonnance,
  });
  Future<TeledocConsultationDto> endConsultation(int id, String ordonnance);
  Future<void> deleteConsultation(int id);
  Future<TeledocConsultationDto> choosePharmacy(
    int consultationId,
    int pharmacyId,
  );

  // ---- Pharmacies de garde ----
  Future<List<TeledocPharmacyDto>> nearestPharmacies({
    required double lat,
    required double lng,
    int limit = 10,
  });
}
