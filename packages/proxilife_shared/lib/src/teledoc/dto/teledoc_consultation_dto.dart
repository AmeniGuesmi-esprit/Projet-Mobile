import '../teledoc_enums.dart';

/// A consultation as returned by the API, with the request summary and the
/// names needed by the history screens (no extra round-trip).
class TeledocConsultationDto {
  const TeledocConsultationDto({
    required this.id,
    required this.dateDebut,
    required this.type,
    required this.idDemande,
    required this.motif,
    required this.urgence,
    required this.statutDemande,
    this.dateFin,
    this.ordonnance,
    this.idPharmacie,
    this.pharmacieNom,
    this.idMedecin,
    this.medecinNom,
    this.patientNom,
  });

  final int id;
  final String dateDebut;
  final String? dateFin;
  final TeledocConsultationType type;
  final String? ordonnance;
  final int? idPharmacie;
  final String? pharmacieNom;
  final int idDemande;
  final int? idMedecin;
  final String? medecinNom;
  final String? patientNom;
  final String motif;
  final TeledocUrgency urgence;
  final TeledocRequestStatus statutDemande;

  /// `date_fin` is set when the consultation ends (or is interrupted).
  bool get estTerminee => dateFin != null;

  factory TeledocConsultationDto.fromJson(Map<String, dynamic> json) =>
      TeledocConsultationDto(
        id: json['id'] as int,
        dateDebut: json['date_debut'] as String,
        dateFin: json['date_fin'] as String?,
        type: TeledocConsultationType.parse(json['type'] as String),
        ordonnance: json['ordonnance'] as String?,
        idPharmacie: json['id_pharmacie'] as int?,
        pharmacieNom: json['pharmacie_nom'] as String?,
        idDemande: json['id_demande'] as int,
        idMedecin: json['id_medecin'] as int?,
        medecinNom: json['medecin_nom'] as String?,
        patientNom: json['patient_nom'] as String?,
        motif: json['motif'] as String,
        urgence: TeledocUrgency.parse(json['urgence'] as String),
        statutDemande:
            TeledocRequestStatus.parse(json['statut_demande'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date_debut': dateDebut,
        'date_fin': dateFin,
        'type': type.apiValue,
        'ordonnance': ordonnance,
        'id_pharmacie': idPharmacie,
        'pharmacie_nom': pharmacieNom,
        'id_demande': idDemande,
        'id_medecin': idMedecin,
        'medecin_nom': medecinNom,
        'patient_nom': patientNom,
        'motif': motif,
        'urgence': urgence.apiValue,
        'statut_demande': statutDemande.apiValue,
      };
}
