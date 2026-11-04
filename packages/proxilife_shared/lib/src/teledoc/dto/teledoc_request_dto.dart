import '../teledoc_enums.dart';

/// A consultation request (`DemandeConsultation`) as returned by the API.
///
/// [positionFile] / [tempsEstimeMinutes] are derived values, computed by the
/// server on every read; they are `null` unless the request is waiting.
/// The photo file name is never exposed, only [aPhoto].
class TeledocRequestDto {
  const TeledocRequestDto({
    required this.id,
    required this.motif,
    required this.description,
    required this.urgence,
    required this.aPhoto,
    required this.statut,
    required this.creeLe,
    required this.modifieLe,
    this.positionFile,
    this.tempsEstimeMinutes,
    this.patientNom,
    this.transactionId,
    this.consultationId,
  });

  final int id;
  final String motif;
  final String description;
  final TeledocUrgency urgence;
  final bool aPhoto;
  final TeledocRequestStatus statut;
  final int? positionFile;
  final int? tempsEstimeMinutes;
  final String? patientNom;
  final int? transactionId;
  final int? consultationId;
  final String creeLe;
  final String modifieLe;

  factory TeledocRequestDto.fromJson(Map<String, dynamic> json) =>
      TeledocRequestDto(
        id: json['id'] as int,
        motif: json['motif'] as String,
        description: json['description'] as String,
        urgence: TeledocUrgency.parse(json['urgence'] as String),
        aPhoto: json['a_photo'] as bool,
        statut: TeledocRequestStatus.parse(json['statut'] as String),
        positionFile: json['position_file'] as int?,
        tempsEstimeMinutes: json['temps_estime_minutes'] as int?,
        patientNom: json['patient_nom'] as String?,
        transactionId: json['transaction_id'] as int?,
        consultationId: json['consultation_id'] as int?,
        creeLe: json['cree_le'] as String,
        modifieLe: json['modifie_le'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'motif': motif,
        'description': description,
        'urgence': urgence.apiValue,
        'a_photo': aPhoto,
        'statut': statut.apiValue,
        'position_file': positionFile,
        'temps_estime_minutes': tempsEstimeMinutes,
        'patient_nom': patientNom,
        'transaction_id': transactionId,
        'consultation_id': consultationId,
        'cree_le': creeLe,
        'modifie_le': modifieLe,
      };
}
