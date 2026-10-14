import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../api_error.dart';
import '../auth/auth_middleware.dart';
import '../http_helpers.dart';
import '../repositories/teledoc_consultation_repository.dart';
import '../repositories/teledoc_pharmacy_repository.dart';
import '../repositories/teledoc_request_repository.dart';
import '../services/teledoc_payment_gateway.dart';
import '../services/teledoc_photo_store.dart';
import '../services/teledoc_queue_service.dart';
import '../services/teledoc_service.dart';

/// Wires the TeleDoc module; `app.dart` mounts it with a single line.
///
/// [payments] defaults to the mock gateway (CONCEPTION.md §7): plugging the
/// real Payment module (Étape 11) only changes this default. [uploadsDir] is
/// relative to the server's working directory (`server/`).
Router buildTeledocModule(
  Database db, {
  TeledocPaymentGateway payments = const MockTeledocPaymentGateway(),
  String uploadsDir = 'uploads/teledoc',
  DateTime Function()? clock,
}) {
  final requests = TeledocRequestRepository(db);
  final consultations = TeledocConsultationRepository(db);
  return buildTeledocRoutes(TeledocService(
    db: db,
    requests: requests,
    consultations: consultations,
    pharmacies: TeledocPharmacyRepository(db),
    photos: TeledocPhotoStore(uploadsDir),
    payments: payments,
    queue: TeledocQueueService(
      db: db,
      requests: requests,
      consultations: consultations,
    ),
    clock: clock,
  ));
}

/// TeleDoc REST routes (mounted behind [requireAuth]); see CONCEPTION.md §3.
Router buildTeledocRoutes(TeledocService service) {
  final router = Router();

  // ---- Demandes de consultation ----

  router.post('/teledoc/requests', (Request request) {
    return guard(() async {
      final body = await readJsonBody(request);
      final dto = await service.createRequest(
        _caller(request),
        motif: _string(body, 'motif'),
        description: _string(body, 'description'),
        urgence: _string(body, 'urgence'),
        photoBase64: _string(body, 'photo_base64'),
      );
      return jsonResponse(dto.toJson(), status: 201);
    });
  });

  router.get('/teledoc/requests', (Request request) {
    return guard(() async {
      final statut = request.url.queryParameters['statut'];
      final list = await service.listRequests(
        _caller(request),
        statut: statut == null ? null : TeledocRequestStatus.parse(statut),
      );
      return jsonResponse({'items': list.map((d) => d.toJson()).toList()});
    });
  });

  router.get('/teledoc/requests/<id|[0-9]+>', (Request request, String id) {
    return guard(() async {
      final dto = await service.getRequest(_caller(request), int.parse(id));
      return jsonResponse(dto.toJson());
    });
  });

  router.patch('/teledoc/requests/<id|[0-9]+>', (Request request, String id) {
    return guard(() async {
      final body = await readJsonBody(request);
      final dto = await service.updateRequest(
        _caller(request),
        int.parse(id),
        motif: _string(body, 'motif'),
        description: _string(body, 'description'),
        urgence: _string(body, 'urgence'),
        photoBase64: _string(body, 'photo_base64'),
        removePhoto: _bool(body, 'supprimer_photo'),
      );
      return jsonResponse(dto.toJson());
    });
  });

  router.post('/teledoc/requests/<id|[0-9]+>/cancel',
      (Request request, String id) {
    return guard(() async {
      final dto = await service.cancelRequest(_caller(request), int.parse(id));
      return jsonResponse(dto.toJson());
    });
  });

  router.get('/teledoc/requests/<id|[0-9]+>/photo',
      (Request request, String id) {
    return guard(() async {
      final photo = await service.requestPhoto(_caller(request), int.parse(id));
      return Response.ok(photo.bytes, headers: {
        'content-type': photo.contentType,
        // Medical data: never cached by intermediaries, never sniffed.
        'cache-control': 'private, no-store',
        'x-content-type-options': 'nosniff',
      });
    });
  });

  // ---- File d'attente virtuelle ----

  router.get('/teledoc/requests/<id|[0-9]+>/queue-status',
      (Request request, String id) {
    return guard(() async {
      final dto = await service.queueStatus(_caller(request), int.parse(id));
      return jsonResponse(dto.toJson());
    });
  });

  router.get('/teledoc/queue', (Request request) {
    return guard(() async {
      final list = await service.waitingQueue(_caller(request));
      return jsonResponse({'items': list.map((d) => d.toJson()).toList()});
    });
  });

  // ---- Consultations ----

  router.post('/teledoc/consultations', (Request request) {
    return guard(() async {
      final body = await readJsonBody(request);
      final dto = await service.startNextConsultation(
        _caller(request),
        type: _string(body, 'type'),
      );
      return jsonResponse(dto.toJson(), status: 201);
    });
  });

  router.get('/teledoc/consultations', (Request request) {
    return guard(() async {
      final list = await service.listConsultations(_caller(request));
      return jsonResponse({'items': list.map((c) => c.toJson()).toList()});
    });
  });

  router.get('/teledoc/consultations/<id|[0-9]+>',
      (Request request, String id) {
    return guard(() async {
      final dto =
          await service.getConsultation(_caller(request), int.parse(id));
      return jsonResponse(dto.toJson());
    });
  });

  router.patch('/teledoc/consultations/<id|[0-9]+>',
      (Request request, String id) {
    return guard(() async {
      final body = await readJsonBody(request);
      final dto = await service.updateConsultation(
        _caller(request),
        int.parse(id),
        type: _string(body, 'type'),
        ordonnance: _string(body, 'ordonnance'),
      );
      return jsonResponse(dto.toJson());
    });
  });

  router.post('/teledoc/consultations/<id|[0-9]+>/end',
      (Request request, String id) {
    return guard(() async {
      final body = await readJsonBody(request);
      final dto = await service.endConsultation(
        _caller(request),
        int.parse(id),
        ordonnance: _string(body, 'ordonnance'),
      );
      return jsonResponse(dto.toJson());
    });
  });

  router.delete('/teledoc/consultations/<id|[0-9]+>',
      (Request request, String id) {
    return guard(() async {
      await service.deleteConsultation(_caller(request), int.parse(id));
      return Response(204);
    });
  });

  router.patch('/teledoc/consultations/<id|[0-9]+>/pharmacy',
      (Request request, String id) {
    return guard(() async {
      final body = await readJsonBody(request);
      final pharmacyId = body['id_pharmacie'];
      if (pharmacyId is! int) {
        throw ApiError.badRequest('id_pharmacie (entier) requis');
      }
      final dto = await service.choosePharmacy(
        _caller(request),
        int.parse(id),
        pharmacyId: pharmacyId,
      );
      return jsonResponse(dto.toJson());
    });
  });

  // ---- Pharmacies de garde ----

  router.get('/teledoc/pharmacies/on-duty', (Request request) {
    return guard(() async {
      final params = request.url.queryParameters;
      final lat = double.tryParse(params['lat'] ?? '');
      final lng = double.tryParse(params['lng'] ?? '');
      if (lat == null || lng == null) {
        throw ApiError.badRequest('Paramètres lat et lng requis');
      }
      // Any authenticated user may search (role checked like elsewhere).
      _caller(request);
      final list = await service.nearestOnDutyPharmacies(
        lat: lat,
        lng: lng,
        limit: int.tryParse(params['limit'] ?? '') ?? 10,
      );
      return jsonResponse({'items': list.map((p) => p.toJson()).toList()});
    });
  });

  return router;
}

TeledocUser _caller(Request request) => TeledocUser.fromRole(
      request.userId,
      UserRole.parse(request.userRow['role'] as String),
    );

/// Optional string field; a value of another JSON type is a client error
/// (instead of a cast failure surfacing as a 500).
String? _string(Map<String, dynamic> body, String key) {
  final value = body[key];
  if (value == null || value is String) return value as String?;
  throw ApiError.badRequest('Le champ $key doit être un texte');
}

bool _bool(Map<String, dynamic> body, String key) {
  final value = body[key];
  if (value == null) return false;
  if (value is bool) return value;
  throw ApiError.badRequest('Le champ $key doit être un booléen');
}
