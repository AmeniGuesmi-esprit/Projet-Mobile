import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../api_error.dart';
import '../auth/auth_middleware.dart';
import '../http_helpers.dart';
import '../services/payment_service.dart';

/// Payment method + transaction routes (mounted behind [requireAuth]).
Router buildPaymentRoutes(PaymentService payments) {
  final router = Router();

  // ---- Moyens de paiement ----

  router.get('/payment-methods', (Request request) {
    return guard(() async {
      final list = await payments.listMethods(request.userId);
      return jsonResponse({'items': list.map((m) => m.toJson()).toList()});
    });
  });

  router.post('/payment-methods', (Request request) {
    return guard(() async {
      final body = await readJsonBody(request);
      final dto = await payments.addMethod(
        request.userId,
        type: PaymentMethodType.parse(body['type'] as String? ?? ''),
        numeroCarte: body['numero_carte'] as String?,
        nomTitulaire: body['nom_titulaire'] as String?,
        dateExpiration: body['date_expiration'] as String?,
        parDefaut: body['par_defaut'] as bool? ?? false,
      );
      return jsonResponse(dto.toJson(), status: 201);
    });
  });

  router.patch('/payment-methods/<id|[0-9]+>', (Request request, String id) {
    return guard(() async {
      final body = await readJsonBody(request);
      final dto = await payments.updateMethod(
        request.userId,
        int.parse(id),
        nomTitulaire: body['nom_titulaire'] as String?,
        dateExpiration: body['date_expiration'] as String?,
      );
      return jsonResponse(dto.toJson());
    });
  });

  router.patch('/payment-methods/<id|[0-9]+>/default',

      (Request request, String id) {
    return guard(() async {
      await payments.setDefaultMethod(request.userId, int.parse(id));
      return jsonResponse({'message': 'Moyen de paiement par défaut mis à jour'});
    });
  });

  router.delete('/payment-methods/<id|[0-9]+>', (Request request, String id) {
    return guard(() async {
      await payments.deleteMethod(request.userId, int.parse(id));
      return Response(204);
    });
  });

  // ---- Transactions ----

  router.get('/transactions', (Request request) {
    return guard(() async {
      final params = request.url.queryParameters;
      final statut = params['statut'] == null
          ? null
          : TransactionStatus.parse(params['statut']!);
      final service = params['type_service'] == null
          ? null
          : ServiceType.parse(params['type_service']!);
      final list = await payments.listTransactions(
        request.userId,
        statut: statut,
        service: service,
      );
      return jsonResponse({'items': list.map((t) => t.toJson()).toList()});
    });
  });

  router.post('/transactions', (Request request) {
    return guard(() async {
      final body = await readJsonBody(request);
      final montant = body['montant_centimes'];
      if (montant is! int) {
        throw ApiError.badRequest('montant_centimes (entier) requis');
      }
      final dto = await payments.createTransaction(
        request.userId,
        montantCentimes: montant,
        beneficiaireEmail: body['beneficiaire_email'] as String? ?? '',
        typeService: ServiceType.parse(body['type_service'] as String? ?? ''),
        idReference: body['id_reference'] as String?,
        moyenPaiementId: body['id_moyen_paiement'] as int?,
      );
      return jsonResponse(dto.toJson(), status: 201);
    });
  });

  router.get('/transactions/<id|[0-9]+>', (Request request, String id) {
    return guard(() async {
      final row = request.userRow;
      final role = UserRole.parse(row['role'] as String);
      final dto =
          await payments.getTransaction(int.parse(id), request.userId, role);
      return jsonResponse(dto.toJson());
    });
  });

  router.patch('/transactions/<id|[0-9]+>/status',

      (Request request, String id) {
    return guard(() async {
      final body = await readJsonBody(request);
      final statutCible =
          TransactionStatus.parse(body['statut'] as String? ?? '');
      if (statutCible != TransactionStatus.rembourse) {
        throw ApiError.badRequest(
            'Seul le statut rembourse est accepté ici');
      }
      final role = UserRole.parse(request.userRow['role'] as String);
      final dto =
          await payments.refund(int.parse(id), request.userId, role);
      return jsonResponse(dto.toJson());
    });
  });

  router.delete('/transactions/<id|[0-9]+>', (Request request, String id) {
    return guard(() async {
      final role = UserRole.parse(request.userRow['role'] as String);
      await payments.cancel(int.parse(id), request.userId, role);
      return Response(204);
    });
  });

  return router;
}
