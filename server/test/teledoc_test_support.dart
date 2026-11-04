import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:proxilife_server/src/auth/auth_middleware.dart';
import 'package:proxilife_server/src/auth/session_service.dart';
import 'package:proxilife_server/src/db/database.dart';
import 'package:proxilife_server/src/db/teledoc_seed.dart';
import 'package:proxilife_server/src/repositories/user_repository.dart';
import 'package:proxilife_server/src/routes/teledoc_routes.dart';
import 'package:proxilife_server/src/services/teledoc_payment_gateway.dart';
import 'package:shelf/shelf.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Inserts an active user directly (no password hashing: tests open
/// sessions through `SessionService`, never through `/auth/login`).
Future<int> insertTestUser(
  Database db,
  String email,
  String role, {
  String prenom = 'Test',
  String nom = 'Utilisateur',
  String statut = 'actif',
}) =>
    db.insert('utilisateur', {
      'nom': nom,
      'prenom': prenom,
      'email': email,
      'telephone': '98000000',
      'mot_de_passe_hash': 'not-a-real-hash',
      'role': role,
      'statut_compte': statut,
      'rib': role == 'client' ? null : '30004000011234567890173',
      'solde_centimes': 0,
      'cree_le': DateTime.now().toIso8601String(),
    });

Future<int> insertTestRequest(
  Database db,
  int patientId, {
  String statut = 'en_attente',
  String urgence = 'moyenne',
  DateTime? creeLe,
}) {
  final at = (creeLe ?? DateTime.now()).toIso8601String();
  return db.insert('teledoc_demande', {
    'motif': 'Motif test',
    'description': 'Description de test suffisante',
    'urgence': urgence,
    'statut': statut,
    'patient_id': patientId,
    'cree_le': at,
    'modifie_le': at,
  });
}

// ---------------------------------------------------------------------------
// API test harness
// ---------------------------------------------------------------------------

/// Payment gateway spy: records calls, can be told to refuse.
class RecordingPaymentGateway implements TeledocPaymentGateway {
  final List<({int patientId, int amountCents, int requestId})> charges = [];
  final List<int> refunds = [];
  bool declineCharges = false;
  bool declineRefunds = false;

  @override
  Future<int> charge({
    required int patientId,
    required int amountCents,
    required int requestId,
  }) async {
    if (declineCharges) throw const TeledocPaymentDeclined('Solde insuffisant');
    charges.add(
        (patientId: patientId, amountCents: amountCents, requestId: requestId));
    return 1000 + requestId;
  }

  @override
  Future<void> refund(
      {required int transactionId, required int patientId}) async {
    if (declineRefunds) throw const TeledocPaymentDeclined('Refus banque');
    refunds.add(transactionId);
  }
}

/// TeleDoc routes behind the real [requireAuth] middleware, on an in-memory
/// database and a temporary uploads directory.
class TeledocTestServer {
  TeledocTestServer._(
      this.database, this.handler, this.uploads, this.payments, this._sessions);

  final AppDatabase database;
  final Handler handler;
  final Directory uploads;
  final RecordingPaymentGateway payments;
  final SessionService _sessions;

  Database get db => database.db;

  static Future<TeledocTestServer> create({DateTime Function()? clock}) async {
    final database = await AppDatabase.inMemory();
    final uploads = await Directory.systemTemp.createTemp('teledoc_uploads');
    final payments = RecordingPaymentGateway();
    final sessions = SessionService(database.db, UserRepository(database.db));
    final handler = const Pipeline()
        .addMiddleware(requireAuth(sessions))
        .addHandler(buildTeledocModule(
          database.db,
          payments: payments,
          uploadsDir: uploads.path,
          clock: clock,
        ).call);
    return TeledocTestServer._(database, handler, uploads, payments, sessions);
  }

  Future<void> close() async {
    await database.close();
    if (await uploads.exists()) await uploads.delete(recursive: true);
  }

  /// Creates a user and returns (id, bearer token).
  Future<(int, String)> user(String email, String role,
      {String prenom = 'Test'}) async {
    final id = await insertTestUser(db, email, role, prenom: prenom);
    return (id, await _sessions.createSession(id));
  }

  Future<void> insertPharmacies() async {
    for (final p in teledocDemoPharmacies) {
      await db.insert('teledoc_pharmacie', {
        'nom': p.nom,
        'adresse': p.adresse,
        'telephone': p.telephone,
        'latitude': p.latitude,
        'longitude': p.longitude,
        'de_garde': p.deGarde ? 1 : 0,
      });
    }
  }

  List<String> storedPhotos() =>
      uploads.listSync().map((f) => p.basename(f.path)).toList();

  Future<Response> raw(String verb, String path,
      {Object? body, String? token}) async {
    return handler(Request(
      verb,
      Uri.parse('http://test$path'),
      body: body == null ? null : jsonEncode(body),
      headers: {
        if (body != null) 'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      },
    ));
  }

  Future<(int, Map<String, dynamic>)> call(String verb, String path,
      {Object? body, String? token}) async {
    final response = await raw(verb, path, body: body, token: token);
    final text = await response.readAsString();
    return (
      response.statusCode,
      text.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(text) as Map<String, dynamic>,
    );
  }
}

/// Smallest byte strings carrying a real JPEG / PNG / GIF signature (the
/// server only trusts the signature, so this is enough).
final String fakeJpegBase64 =
    base64.encode([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(64, 1)]);
final String fakePngBase64 = base64.encode(
    [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, ...List.filled(64, 2)]);
final String fakeGifBase64 =
    base64.encode('GIF89a'.codeUnits + List.filled(64, 3));

Map<String, dynamic> validRequestBody(
        {String? photo, String urgence = 'moyenne'}) =>
    {
      'motif': 'Fièvre',
      'description': 'Fièvre à 39 °C depuis hier soir',
      'urgence': urgence,
      if (photo != null) 'photo_base64': photo,
    };
