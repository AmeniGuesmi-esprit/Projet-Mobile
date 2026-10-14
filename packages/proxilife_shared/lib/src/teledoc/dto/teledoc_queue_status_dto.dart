import '../teledoc_enums.dart';

/// Lightweight payload polled by the patient's waiting screen.
class TeledocQueueStatusDto {
  const TeledocQueueStatusDto({
    required this.idDemande,
    required this.statut,
    this.positionFile,
    this.tempsEstimeMinutes,
    this.taille,
    this.consultationId,
    this.typeConsultation,
  });

  final int idDemande;
  final TeledocRequestStatus statut;
  final int? positionFile;
  final int? tempsEstimeMinutes;

  /// Number of waiting requests (whole queue).
  final int? taille;

  /// Set once a doctor has started the consultation.
  final int? consultationId;
  final TeledocConsultationType? typeConsultation;

  factory TeledocQueueStatusDto.fromJson(Map<String, dynamic> json) =>
      TeledocQueueStatusDto(
        idDemande: json['id_demande'] as int,
        statut: TeledocRequestStatus.parse(json['statut'] as String),
        positionFile: json['position_file'] as int?,
        tempsEstimeMinutes: json['temps_estime_minutes'] as int?,
        taille: json['taille_file'] as int?,
        consultationId: json['consultation_id'] as int?,
        typeConsultation: json['type_consultation'] == null
            ? null
            : TeledocConsultationType.parse(
                json['type_consultation'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id_demande': idDemande,
        'statut': statut.apiValue,
        'position_file': positionFile,
        'temps_estime_minutes': tempsEstimeMinutes,
        'taille_file': taille,
        'consultation_id': consultationId,
        'type_consultation': typeConsultation?.apiValue,
      };
}
