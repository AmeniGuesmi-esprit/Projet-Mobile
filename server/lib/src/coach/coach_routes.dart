import 'dart:async';
import 'dart:developer' as developer;

import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../api_error.dart';
import '../auth/auth_middleware.dart';
import '../http_helpers.dart';
import 'coach_service.dart';

/// CoachProche REST routes (mounted behind requireAuth by `buildApp`).
///
///   Séances (everyone)     GET  /coach/seances            search + filters
///                          GET  /coach/seances/<id>
///   Séances (coach)        POST /coach/seances            publish
///                          PUT  /coach/seances/<id>       modify
///                          POST /coach/seances/<id>/cancel
///                          GET  /coach/mes-seances
///                          GET  /coach/seances/<id>/inscrits
///   Réservations (client)  POST /coach/reservations
///                          GET  /coach/reservations
///                          GET  /coach/reservations/<id>
///                          POST /coach/reservations/<id>/cancel
///                          PUT  /coach/reservations/<id>/suivi   pas, BPM
///   Présence (coach)       POST /coach/scan
///   Notifications          GET  /coach/notifications[?non_lues=1]
///                          POST /coach/notifications/read-all
///                          POST /coach/notifications/<id>/read
Router buildCoachRoutes(CoachService service) {
  final router = Router();

  // ---- Sessions: search (everyone) ----

  router.get('/coach/seances', (Request request) {
    return guard(() async {
      final q = request.url.queryParameters;
      final list = await service.search(
        viewerId: request.userId,
        type: _enumParam(q['type'], CoachSessionType.parse, 'Type invalide'),
        niveau: _enumParam(q['niveau'], CoachLevel.parse, 'Niveau invalide'),
        lieu: q['lieu'],
        from: _dateParam(q['date_debut']),
        to: _dateParam(q['date_fin']),
        prixMaxCentimes: _intParam(q['prix_max_centimes'], 'Prix invalide'),
        latitude: _doubleParam(q['lat'], 'Position invalide'),
        longitude: _doubleParam(q['lng'], 'Position invalide'),
        rayonKm: _doubleParam(q['rayon_km'], 'Rayon invalide'),
        sortByDistance: q['tri'] == 'distance',
      );
      return jsonResponse({'items': list.map((s) => s.toJson()).toList()});
    });
  });

  router.get('/coach/seances/<id|[0-9]+>', (Request request, String id) {
    return guard(() async {
      final dto =
          await service.getSession(_id(id), viewerId: request.userId);
      return jsonResponse(dto.toJson());
    });
  });

  // ---- Sessions: coach ----

  router.post('/coach/seances', (Request request) {
    return guard(() async {
      _requireCoach(request.userRow);
      final body = await readJsonBody(request);
      final dto = await service.publish(request.userId, body);
      return jsonResponse(dto.toJson(), status: 201);
    });
  });

  router.put('/coach/seances/<id|[0-9]+>', (Request request, String id) {
    return guard(() async {
      _requireCoach(request.userRow);
      final body = await readJsonBody(request);
      final dto = await service.update(request.userId, _id(id), body);
      return jsonResponse(dto.toJson());
    });
  });

  router.post('/coach/seances/<id|[0-9]+>/cancel',
      (Request request, String id) {
    return guard(() async {
      _requireCoach(request.userRow);
      final dto = await service.cancelSession(request.userId, _id(id));
      return jsonResponse(dto.toJson());
    });
  });

  router.get('/coach/mes-seances', (Request request) {
    return guard(() async {
      _requireCoach(request.userRow);
      final list = await service.listMine(request.userId);
      return jsonResponse({'items': list.map((s) => s.toJson()).toList()});
    });
  });

  router.get('/coach/seances/<id|[0-9]+>/inscrits',
      (Request request, String id) {
    return guard(() async {
      _requireCoach(request.userRow);
      final list = await service.listAttendees(request.userId, _id(id));
      return jsonResponse({'items': list.map((r) => r.toJson()).toList()});
    });
  });

  // ---- Bookings (client) ----

  router.post('/coach/reservations', (Request request) {
    return guard(() async {
      final body = await readJsonBody(request);
      final seanceId = body['seance_id'];
      if (seanceId is! int) throw ApiError.badRequest('Séance manquante');
      final method = body['moyen_paiement_id'];
      if (method != null && method is! int) {
        throw ApiError.badRequest('Moyen de paiement invalide');
      }
      final dto = await service.reserve(
        clientId: request.userId,
        seanceId: seanceId,
        moyenPaiementId: method as int?,
      );
      return jsonResponse(dto.toJson(), status: 201);
    });
  });

  router.get('/coach/reservations', (Request request) {
    return guard(() async {
      final list = await service.listForClient(request.userId);
      return jsonResponse({'items': list.map((r) => r.toJson()).toList()});
    });
  });

  router.get('/coach/reservations/<id|[0-9]+>', (Request request, String id) {
    return guard(() async {
      final dto =
          await service.getBooking(_id(id), viewerId: request.userId);
      if (dto == null) throw ApiError.notFound('Réservation introuvable');
      return jsonResponse(dto.toJson());
    });
  });

  router.post('/coach/reservations/<id|[0-9]+>/cancel',
      (Request request, String id) {
    return guard(() async {
      final dto =
          await service.cancelBooking(_id(id), clientId: request.userId);
      return jsonResponse(dto.toJson());
    });
  });

  router.put('/coach/reservations/<id|[0-9]+>/suivi',
      (Request request, String id) {
    return guard(() async {
      final body = await readJsonBody(request);
      final dto = await service.recordMetrics(
        _id(id),
        clientId: request.userId,
        pas: _bodyInt(body, 'pas', 'Nombre de pas invalide'),
        frequenceCardiaque: _bodyInt(body, 'frequence_cardiaque',
            'Fréquence cardiaque invalide'),
      );
      return jsonResponse(dto.toJson());
    });
  });

  // ---- Presence check (coach) ----

  router.post('/coach/scan', (Request request) {
    return guard(() async {
      _requireCoach(request.userRow);
      final body = await readJsonBody(request);
      final token = body['token'];
      if (token is! String || token.trim().isEmpty) {
        throw ApiError.badRequest('QR code manquant');
      }
      final result = await service.scan(request.userId, token);
      return jsonResponse(result.toJson());
    });
  });

  // ---- Notifications ----

  router.get('/coach/notifications', (Request request) {
    return guard(() async {
      final unread = request.url.queryParameters['non_lues'] == '1';
      final list = await service.listNotifications(request.userId,
          unreadOnly: unread);
      return jsonResponse({'items': list.map((n) => n.toJson()).toList()});
    });
  });

  router.post('/coach/notifications/read-all', (Request request) {
    return guard(() async {
      await service.markRead(request.userId);
      return jsonResponse({'ok': true});
    });
  });

  router.post('/coach/notifications/<id|[0-9]+>/read',
      (Request request, String id) {
    return guard(() async {
      await service.markRead(request.userId, id: _id(id));
      return jsonResponse({'ok': true});
    });
  });

  return router;
}

/// Periodic maintenance: reminders before a session. Started by the real
/// server only (tests call the service directly).
Timer startCoachJobs(CoachService service,
    {Duration every = const Duration(minutes: 1)}) {
  var running = false;
  Future<void> tick() async {
    if (running) return; // never overlap two runs
    running = true;
    try {
      await service.sendReminders();
    } catch (e, st) {
      developer.log('Coach job failed',
          error: e, stackTrace: st, name: 'coach');
    } finally {
      running = false;
    }
  }

  unawaited(tick());
  return Timer.periodic(every, (_) => tick());
}

void _requireCoach(Map<String, Object?> userRow) {
  if (UserRole.parse(userRow['role'] as String) != UserRole.coach) {
    throw ApiError.forbidden('Espace réservé aux coachs');
  }
}

int _id(String raw) {
  final id = int.tryParse(raw);
  if (id == null) throw ApiError.notFound('Ressource introuvable');
  return id;
}

T? _enumParam<T>(String? raw, T Function(String) parse, String message) {
  if (raw == null || raw.isEmpty) return null;
  try {
    return parse(raw);
  } on ArgumentError {
    throw ApiError.badRequest(message);
  }
}

int? _intParam(String? raw, String message) {
  if (raw == null || raw.isEmpty) return null;
  return int.tryParse(raw) ?? (throw ApiError.badRequest(message));
}

double? _doubleParam(String? raw, String message) {
  if (raw == null || raw.isEmpty) return null;
  return double.tryParse(raw) ?? (throw ApiError.badRequest(message));
}

DateTime? _dateParam(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toUtc() ??
      (throw ApiError.badRequest('Date invalide'));
}

int? _bodyInt(Map<String, dynamic> body, String key, String message) {
  final value = body[key];
  if (value == null) return null;
  if (value is int) return value;
  throw ApiError.badRequest(message);
}
