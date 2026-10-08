import 'dart:convert';

import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../api_error.dart';
import '../auth/auth_middleware.dart';
import '../repositories/user_repository.dart';
import '../services/auth_service.dart';

import '../http_helpers.dart';

/// Authenticated user profile routes (mounted behind [requireAuth]).
Router buildUserRoutes(UserRepository users, AuthService auth) {
  final router = Router();

  router.get('/users/me', (Request request) {
    return guard(() async {
      final fresh = await users.findById(request.userId);
      if (fresh == null) throw ApiError.notFound('Compte introuvable');
      return jsonResponse(users.toDto(fresh).toJson());
    });
  });

  router.patch('/users/me', (Request request) {
    return guard(() async {
      final body = await readJsonBody(request);

      final nom = body['nom'] as String?;
      final prenom = body['prenom'] as String?;
      final telephone = body['telephone'] as String?;
      final photo = body['photo'] as String?;
      final rib = body['rib'] as String?;
      final clearPhoto = body['photo'] == null && body.containsKey('photo');
      final clearRib = body['rib'] == null && body.containsKey('rib');

      if (nom != null && !isValidName(nom)) {
        throw ApiError.badRequest('Nom invalide');
      }
      if (prenom != null && !isValidName(prenom)) {
        throw ApiError.badRequest('Prénom invalide');
      }
      if (telephone != null && !isValidPhone(telephone)) {
        throw ApiError.badRequest(
            'Téléphone invalide (France : 06…, Tunisie : +216…)');
      }
      if (rib != null && rib.isNotEmpty && !isValidRib(rib)) {
        throw ApiError.badRequest('RIB invalide (vérifiez la clé)');
      }
      if (photo != null) {
        // Photos are base64 JPEG, capped at ~500 KB on the wire.
        if (utf8.encode(photo).length > 500 * 1024) {
          throw ApiError.badRequest('Photo trop lourde (max 500 Ko)');
        }
        try {
          base64Decode(photo);
        } on FormatException {
          throw ApiError.badRequest('Photo invalide (base64 attendu)');
        }
      }

      // RIB rules per role.
      final fresh = await users.findById(request.userId);
      if (fresh == null) throw ApiError.notFound('Compte introuvable');
      final role = UserRole.parse(fresh['role'] as String);
      if (role.requiresRib && ((rib != null && rib.isEmpty) || clearRib)) {
        throw ApiError.badRequest(
            'Un RIB est obligatoire pour votre rôle');
      }

      await users.updateProfile(
        request.userId,
        nom: nom?.trim(),
        prenom: prenom?.trim(),
        telephone: telephone?.trim(),
        photo: photo,
        rib: (rib == null || rib.isEmpty) ? null : rib,
        clearPhoto: clearPhoto,
        clearRib: clearRib && !role.requiresRib,
      );

      final updated = await users.findById(request.userId);
      return jsonResponse(users.toDto(updated!).toJson());
    });
  });

  router.delete('/users/me', (Request request) {
    return guard(() async {
      final body = await readJsonBody(request);
      await auth.deleteAccount(
        request.userId,
        body['mot_de_passe'] as String? ?? '',
      );
      return jsonResponse({'message': 'Compte supprimé'});
    });
  });

  return router;
}
