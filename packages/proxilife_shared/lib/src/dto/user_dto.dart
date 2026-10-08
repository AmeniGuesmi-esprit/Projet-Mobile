import '../enums.dart';

/// Public view of a user. Never exposes the password hash; the RIB is
/// masked (only the last 4 characters are kept visible).
class UserDto {
  const UserDto({
    required this.id,
    required this.nom,
    required this.prenom,
    required this.email,
    required this.telephone,
    required this.role,
    required this.statutCompte,
    required this.soldeCentimes,
    this.photo,
    this.ribMasque,
  });

  final int id;
  final String nom;
  final String prenom;
  final String email;
  final String telephone;
  final String? photo;
  final UserRole role;
  final AccountStatus statutCompte;
  final String? ribMasque;
  final int soldeCentimes;

  factory UserDto.fromJson(Map<String, dynamic> json) => UserDto(
        id: json['id'] as int,
        nom: json['nom'] as String,
        prenom: json['prenom'] as String,
        email: json['email'] as String,
        telephone: json['telephone'] as String,
        photo: json['photo'] as String?,
        role: UserRole.parse(json['role'] as String),
        statutCompte: AccountStatus.parse(json['statut_compte'] as String),
        ribMasque: json['rib_masque'] as String?,
        soldeCentimes: json['solde_centimes'] as int,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nom': nom,
        'prenom': prenom,
        'email': email,
        'telephone': telephone,
        'photo': photo,
        'role': role.apiValue,
        'statut_compte': statutCompte.apiValue,
        'rib_masque': ribMasque,
        'solde_centimes': soldeCentimes,
      };

  String get nomComplet => '$prenom $nom';
}

/// Body returned by a successful login.
class AuthResponseDto {
  const AuthResponseDto({required this.token, required this.utilisateur});

  final String token;
  final UserDto utilisateur;

  factory AuthResponseDto.fromJson(Map<String, dynamic> json) =>
      AuthResponseDto(
        token: json['token'] as String,
        utilisateur: UserDto.fromJson(json['utilisateur'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'token': token,
        'utilisateur': utilisateur.toJson(),
      };
}
