import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../api_error.dart';
import '../auth/auth_middleware.dart';
import '../http_helpers.dart';
import '../services/service_now_service.dart';

/// ServiceNow routes (mounted behind [requireAuth]).
///
///  POST  /service-now/demandes                     (client)
///  GET   /service-now/demandes/mine                (client)
///  GET   /service-now/demandes/disponibles?type=   (prestataire)
///  GET   /service-now/demandes/<id>
///  PATCH /service-now/demandes/<id>                (client, while waiting)
///  POST  /service-now/demandes/<id>/annuler        (client, admin)
///  POST  /service-now/demandes/<id>/accepter       (prestataire)
///  GET   /service-now/interventions/mine           (prestataire)
///  POST  /service-now/interventions/<id>/demarrer  (prestataire)
///  POST  /service-now/interventions/<id>/terminer  (prestataire)
///  POST  /service-now/interventions/<id>/desister  (prestataire)
///  POST  /service-now/interventions/<id>/payer     (client)
///  POST  /service-now/interventions/<id>/evaluer   (client)
///  POST  /service-now/interventions/<id>/en-route  (prestataire)
///  PUT   /service-now/interventions/<id>/position  (prestataire)
///  GET   /service-now/interventions/<id>/suivi
///  POST  /service-now/interventions/<id>/photos    (prestataire)
///  GET   /service-now/interventions/<id>/photos/<avant|apres>
///  GET   /service-now/demandes/<id>/prestataires   (client)
///  GET   /service-now/adresses?q=
///  GET   /service-now/estimation?type=
///  GET, PUT /service-now/profil                    (prestataire)
///  POST  /service-now/notifications/nouvelles
///  GET, PUT /service-now/disponibilites            (prestataire)
///  GET, POST /service-now/demandes/<id>/messages
Router buildServiceNowRoutes(ServiceNowService service) {
  final router = Router();

  Response items(List<DemandeServiceDto> list) =>
      jsonResponse({'items': list.map((d) => d.toJson()).toList()});

  router.post('/service-now/demandes', (Request request) {
    return guard(() async {
      final body = await readJsonBody(request);
      final dto = await service.createDemande(
        request.userId,
        _role(request),
        type: _type(body['type']) ??
            (throw ApiError.badRequest('Type de service obligatoire')),
        description: _string(body['description']) ?? '',
        adresse: _string(body['adresse']) ?? '',
        dateSouhaitee: _date(body['date_souhaitee']) ??
            (throw ApiError.badRequest('Date souhaitée invalide')),
        position: _position(body),
      );
      return jsonResponse(dto.toJson(), status: 201);
    });
  });

  router.get('/service-now/demandes/mine', (Request request) {
    return guard(() async =>
        items(await service.listMine(request.userId, _role(request))));
  });

  router.get('/service-now/demandes/disponibles', (Request request) {
    return guard(() async {
      final type = _type(request.url.queryParameters['type']);
      return items(
          await service.listOpen(request.userId, _role(request), type: type));
    });
  });

  router.get('/service-now/demandes/<id|[0-9]+>', (Request request, String id) {
    return guard(() async {
      final dto =
          await service.getDemande(request.userId, _role(request), int.parse(id));
      return jsonResponse(dto.toJson());
    });
  });

  router.patch('/service-now/demandes/<id|[0-9]+>',
      (Request request, String id) {
    return guard(() async {
      final body = await readJsonBody(request);
      final dto = await service.updateDemande(
        request.userId,
        _role(request),
        int.parse(id),
        type: _type(body['type']),
        description: _string(body['description']),
        adresse: _string(body['adresse']),
        dateSouhaitee: _date(body['date_souhaitee']),
        updatePosition: body.containsKey('latitude'),
        position: _position(body),
      );
      return jsonResponse(dto.toJson());
    });
  });

  router.post('/service-now/demandes/<id|[0-9]+>/annuler',
      (Request request, String id) {
    return guard(() async {
      final dto = await service.cancelDemande(
          request.userId, _role(request), int.parse(id));
      return jsonResponse(dto.toJson());
    });
  });

  router.post('/service-now/demandes/<id|[0-9]+>/accepter',
      (Request request, String id) {
    return guard(() async {
      final body = await readJsonBody(request);
      final dto = await service.acceptDemande(
        request.userId,
        _role(request),
        int.parse(id),
        datePrevue: _date(body['date_prevue']) ??
            (throw ApiError.badRequest('Date prévue invalide')),
        prixCentimes: _int(body['prix_centimes']) ??
            (throw ApiError.badRequest('Prix obligatoire')),
      );
      return jsonResponse(dto.toJson(), status: 201);
    });
  });

  router.get('/service-now/interventions/mine', (Request request) {
    return guard(() async => items(
        await service.listMyInterventions(request.userId, _role(request))));
  });

  router.post('/service-now/interventions/<id|[0-9]+>/demarrer',
      (Request request, String id) {
    return guard(() async {
      final body = await readJsonBody(request);
      final dto = await service.startIntervention(
        request.userId,
        _role(request),
        int.parse(id),
        qrCode: _string(body['qr_code']),
      );
      return jsonResponse(dto.toJson());
    });
  });

  router.post('/service-now/interventions/<id|[0-9]+>/terminer',
      (Request request, String id) {
    return guard(() async {
      final body = await readJsonBody(request);
      final dto = await service.finishIntervention(
        request.userId,
        _role(request),
        int.parse(id),
        rapport: _string(body['rapport']) ?? '',
        prixCentimes: _int(body['prix_centimes']),
      );
      return jsonResponse(dto.toJson());
    });
  });

  router.post('/service-now/interventions/<id|[0-9]+>/desister',
      (Request request, String id) {
    return guard(() async {
      final dto = await service.withdraw(
          request.userId, _role(request), int.parse(id));
      return jsonResponse(dto.toJson());
    });
  });

  router.post('/service-now/interventions/<id|[0-9]+>/payer',
      (Request request, String id) {
    return guard(() async {
      final body = await readJsonBody(request);
      final dto = await service.payIntervention(
        request.userId,
        _role(request),
        int.parse(id),
        moyenPaiementId: _int(body['moyen_paiement_id']),
      );
      return jsonResponse(dto.toJson());
    });
  });

  router.post('/service-now/interventions/<id|[0-9]+>/evaluer',
      (Request request, String id) {
    return guard(() async {
      final body = await readJsonBody(request);
      final dto = await service.rateIntervention(
        request.userId,
        _role(request),
        int.parse(id),
        note: _int(body['note']) ??
            (throw ApiError.badRequest('Note obligatoire')),
        commentaire: _string(body['commentaire']),
      );
      return jsonResponse(dto.toJson());
    });
  });

  router.post('/service-now/interventions/<id|[0-9]+>/en-route',
      (Request request, String id) {
    return guard(() async {
      final dto = await service.startTrip(
        request.userId,
        _role(request),
        int.parse(id),
        position: _requiredPosition(await readJsonBody(request)),
      );
      return jsonResponse(dto.toJson());
    });
  });

  router.put('/service-now/interventions/<id|[0-9]+>/position',
      (Request request, String id) {
    return guard(() async {
      await service.updatePosition(
        request.userId,
        _role(request),
        int.parse(id),
        position: _requiredPosition(await readJsonBody(request)),
      );
      return jsonResponse({'ok': true});
    });
  });

  router.get('/service-now/interventions/<id|[0-9]+>/suivi',
      (Request request, String id) {
    return guard(() async {
      final dto = await service.tracking(
          request.userId, _role(request), int.parse(id));
      return jsonResponse(dto.toJson());
    });
  });

  router.post('/service-now/interventions/<id|[0-9]+>/photos',
      (Request request, String id) {
    return guard(() async {
      final body = await readJsonBody(request);
      final kind = _string(body['type']) ?? '';
      final dto = await service.addPhoto(
        request.userId,
        _role(request),
        int.parse(id),
        kind: InterventionPhotoKind.parse(kind),
        base64Data: _string(body['photo_base64']) ??
            (throw ApiError.badRequest('Photo obligatoire')),
      );
      return jsonResponse(dto.toJson());
    });
  });

  router.get('/service-now/interventions/<id|[0-9]+>/photos/<kind|avant|apres>',
      (Request request, String id, String kind) {
    return guard(() async {
      final photo = await service.readPhoto(
        request.userId,
        _role(request),
        int.parse(id),
        InterventionPhotoKind.parse(kind),
      );
      return Response.ok(photo.bytes,
          headers: {'content-type': photo.contentType});
    });
  });

  router.get('/service-now/demandes/<id|[0-9]+>/prestataires',
      (Request request, String id) {
    return guard(() async {
      final list = await service.nearbyPrestataires(
          request.userId, _role(request), int.parse(id));
      return jsonResponse({'items': list.map((p) => p.toJson()).toList()});
    });
  });

  router.get('/service-now/adresses', (Request request) {
    return guard(() async {
      final list =
          await service.searchAddress(request.url.queryParameters['q'] ?? '');
      return jsonResponse({'items': list.map((a) => a.toJson()).toList()});
    });
  });

  router.get('/service-now/estimation', (Request request) {
    return guard(() async {
      final type = _type(request.url.queryParameters['type']) ??
          (throw ApiError.badRequest('Type de service obligatoire'));
      return jsonResponse((await service.estimatePrice(type)).toJson());
    });
  });

  router.get('/service-now/disponibilites', (Request request) {
    return guard(() async {
      final dto = await service.getCalendar(request.userId, _role(request));
      return jsonResponse(dto.toJson());
    });
  });

  router.put('/service-now/disponibilites', (Request request) {
    return guard(() async {
      final body = await readJsonBody(request);
      final slots = body['creneaux'];
      final days = body['jours_off'];
      if (slots is! List || days is! List) {
        throw ApiError.badRequest('Calendrier invalide');
      }
      final dto = await service.saveCalendar(
        request.userId,
        _role(request),
        creneaux: [
          for (final slot in slots)
            if (slot is Map<String, dynamic> &&
                slot['jour'] is int &&
                slot['debut_minutes'] is int &&
                slot['fin_minutes'] is int)
              DisponibiliteSlotDto.fromJson(slot)
            else
              throw ApiError.badRequest('Créneau invalide'),
        ],
        joursOff: {
          for (final day in days)
            _string(day) ?? (throw ApiError.badRequest('Date invalide')),
        },
      );
      return jsonResponse(dto.toJson());
    });
  });

  Response messages(List<ServiceNowMessageDto> list) =>
      jsonResponse({'items': list.map((m) => m.toJson()).toList()});

  router.get('/service-now/demandes/<id|[0-9]+>/messages',
      (Request request, String id) {
    return guard(() async =>
        messages(await service.listMessages(request.userId, int.parse(id))));
  });

  router.post('/service-now/demandes/<id|[0-9]+>/messages',
      (Request request, String id) {
    return guard(() async {
      final body = await readJsonBody(request);
      return messages(await service.sendMessage(
        request.userId,
        int.parse(id),
        contenu: _string(body['contenu']) ?? '',
      ));
    });
  });

  // A POST because reading them also marks them as delivered.
  router.post('/service-now/notifications/nouvelles', (Request request) {
    return guard(() async {
      final list = await service.takeNotifications(request.userId);
      return jsonResponse({'items': list.map((n) => n.toJson()).toList()});
    });
  });

  router.get('/service-now/profil', (Request request) {
    return guard(() async {
      final dto = await service.getProfile(request.userId, _role(request));
      return jsonResponse(dto.toJson());
    });
  });

  router.put('/service-now/profil', (Request request) {
    return guard(() async {
      final body = await readJsonBody(request);
      final values = body['specialites'];
      if (values is! List) {
        throw ApiError.badRequest('Spécialités obligatoires');
      }
      final dto = await service.saveProfile(
        request.userId,
        _role(request),
        specialites: {
          for (final value in values)
            _type(value) ??
                (throw ApiError.badRequest('Type de service invalide')),
        },
        position: _position(body),
      );
      return jsonResponse(dto.toJson());
    });
  });

  return router;
}

UserRole _role(Request request) =>
    UserRole.parse(request.userRow['role'] as String);

String? _string(Object? value) => value is String ? value : null;

int? _int(Object? value) => value is int ? value : null;

/// Latitude/longitude of the body; null when absent.
({double latitude, double longitude})? _position(Map<String, dynamic> body) {
  final latitude = body['latitude'];
  final longitude = body['longitude'];
  if (latitude == null && longitude == null) return null;
  if (latitude is! num ||
      longitude is! num ||
      !isValidLatLng(latitude.toDouble(), longitude.toDouble())) {
    throw ApiError.badRequest('Position invalide');
  }
  return (latitude: latitude.toDouble(), longitude: longitude.toDouble());
}

({double latitude, double longitude}) _requiredPosition(
  Map<String, dynamic> body,
) =>
    _position(body) ?? (throw ApiError.badRequest('Position obligatoire'));

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

/// Null when absent; an unknown value is the caller's mistake.
ServiceNowType? _type(Object? value) {
  if (value == null || value == '') return null;
  final type = value is String ? ServiceNowType.tryParse(value) : null;
  if (type == null) throw ApiError.badRequest('Type de service invalide');
  return type;
}
