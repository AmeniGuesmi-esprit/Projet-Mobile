import 'dart:math';

import 'package:proxilife_shared/proxilife_shared.dart';

import '../api_error.dart';
import '../auth/passwords.dart';
import '../auth/session_service.dart';
import '../email/email_sender.dart';
import '../repositories/user_repository.dart';
import '../repositories/verification_repository.dart';

/// Business rules for registration, verification e-mail codes, sessions and
/// account deletion.
class AuthService {
  AuthService({
    required this.users,
    required this.verification,
    required this.sessions,
    required this.email,
    PasswordHasher? hasher,
  }) : hasher = hasher ?? const PasswordHasher();

  final UserRepository users;
  final VerificationRepository verification;
  final SessionService sessions;
  final EmailSender email;
  final PasswordHasher hasher;

  /// Registers a user, creates + sends the verification code. Returns the
  /// created user's id.
  Future<int> register({
    required String nom,
    required String prenom,
    required String email,
    required String telephone,
    required String motDePasse,
    required UserRole role,
    String? rib,
  }) async {
    nom = nom.trim();
    prenom = prenom.trim();
    email = normalizeEmail(email);
    telephone = telephone.trim();

    if (!isValidName(nom)) {
      throw ApiError.badRequest('Nom invalide (lettres uniquement)');
    }
    if (!isValidName(prenom)) {
      throw ApiError.badRequest('Prénom invalide (lettres uniquement)');
    }
    if (!isValidEmail(email)) {
      throw ApiError.badRequest('Adresse e-mail invalide');
    }
    if (!isValidPhone(telephone)) {
      throw ApiError.badRequest(
          'Téléphone invalide (France : 06…, Tunisie : +216…)');
    }
    final passwordError = passwordPolicyError(motDePasse);
    if (passwordError != null) throw ApiError.badRequest(passwordError);

    final trimmedRib = rib?.trim();
    if (role.requiresRib) {
      if (trimmedRib == null || trimmedRib.isEmpty) {
        throw ApiError.badRequest(
          'Un RIB est obligatoire pour le rôle ${role.apiValue}',
        );
      }
      if (!isValidRib(trimmedRib)) {
        throw ApiError.badRequest('RIB invalide (vérifiez la clé)');
      }
    } else if (trimmedRib != null &&
        trimmedRib.isNotEmpty &&
        !isValidRib(trimmedRib)) {
      throw ApiError.badRequest('RIB invalide (vérifiez la clé)');
    }

    if (await users.findByEmail(email) != null) {
      throw ApiError.conflict('Un compte existe déjà avec cet e-mail');
    }

    final id = await users.insert(
      nom: nom,
      prenom: prenom,
      email: email,
      telephone: telephone,
      motDePasseHash: hasher.hashPassword(motDePasse),
      role: role,
      rib: trimmedRib == null || trimmedRib.isEmpty ? null : trimmedRib,
    );

    await _issueCode(id, email, prenom);
    return id;
  }

  /// Verifies the 6-digit code. On success the account becomes `actif`.
  Future<void> verify(String email, String code) async {
    email = normalizeEmail(email);
    final user = await users.findByEmail(email);
    if (user == null) throw ApiError.notFound('Aucun compte avec cet e-mail');

    final statut = AccountStatus.parse(user['statut_compte'] as String);
    if (statut == AccountStatus.actif) return; // Already verified.

    final codeRow = await verification.latestPending(user['id'] as int);
    if (codeRow == null) {
      throw ApiError.badRequest(
          'Aucun code en attente : demandez un nouveau code');
    }
    if (verification.isExpired(codeRow)) {
      throw ApiError.gone('Le code a expiré : demandez un nouveau code');
    }
    if ((codeRow['tentatives'] as int) >= VerificationRepository.maxAttempts) {
      throw ApiError.badRequest(
          'Trop de tentatives : demandez un nouveau code');
    }
    final attemptsMade = codeRow['tentatives'] as int;
    if (codeRow['code_hash'] != verification.hashOf(email, code.trim())) {
      await verification.incrementAttempts(codeRow['id'] as int);
      final remaining =
          VerificationRepository.maxAttempts - attemptsMade - 1;
      throw ApiError.badRequest(
        remaining > 0
            ? 'Code incorrect ($remaining essai${remaining > 1 ? 's' : ''} restant${remaining > 1 ? 's' : ''})'
            : 'Trop de tentatives : demandez un nouveau code',
      );
    }

    await verification.markValidated(codeRow['id'] as int);
    await users.updateStatus(user['id'] as int, AccountStatus.actif);
  }

  Future<void> resend(String email) async {
    email = normalizeEmail(email);
    final user = await users.findByEmail(email);
    if (user == null) throw ApiError.notFound('Aucun compte avec cet e-mail');
    final statut = AccountStatus.parse(user['statut_compte'] as String);
    if (statut == AccountStatus.actif) {
      throw ApiError.badRequest('Ce compte est déjà vérifié');
    }
    await _issueCode(user['id'] as int, email, user['prenom'] as String);
  }

  /// Authenticates. 401 on bad credentials, 403 if the account isn't
  /// verified/active.
  Future<AuthResponseDto> login(String email, String motDePasse) async {
    email = normalizeEmail(email);
    final user = await users.findByEmail(email);
    final passwordOk = user != null &&
        hasher.verifyPassword(
            motDePasse, user['mot_de_passe_hash'] as String);
    if (!passwordOk) {
      throw ApiError.unauthorized('E-mail ou mot de passe incorrect');
    }
    final statut = AccountStatus.parse(user['statut_compte'] as String);
    if (statut == AccountStatus.enAttenteVerification) {
      throw ApiError.forbidden(
          'Compte non vérifié : saisissez le code reçu par e-mail');
    }
    if (statut == AccountStatus.suspendu) {
      throw ApiError.forbidden('Compte suspendu : contactez le support');
    }

    final token = await sessions.createSession(user['id'] as int);
    return AuthResponseDto(token: token, utilisateur: users.toDto(user));
  }

  Future<void> logout(String token) => sessions.revoke(token);

  /// Validations déléguées au service de paiement via [users].
  Future<void> deleteAccount(int userId, String motDePasse) async {
    final user = await users.findById(userId);
    if (user == null) throw ApiError.notFound('Compte introuvable');
    if (!hasher.verifyPassword(
        motDePasse, user['mot_de_passe_hash'] as String)) {
      throw ApiError.forbidden('Mot de passe incorrect');
    }
    if (users.soldeOf(user) > 0) {
      throw ApiError.conflict(
          'Solde non nul : retirez ou dépensez votre solde avant de supprimer le compte');
    }
    if (await users.hasPendingTransactions(userId)) {
      throw ApiError.conflict(
          'Transactions en attente : annulez-les avant de supprimer le compte');
    }
    await users.deleteAccount(userId);
  }

  Future<void> _issueCode(int userId, String email, String prenom) async {
    final code = (Random.secure().nextInt(900000) + 100000).toString();
    await verification.create(
      utilisateurId: userId,
      email: email,
      code: code,
    );
    await this
        .email
        .sendVerificationCode(to: email, prenom: prenom, code: code);
  }
}
