import 'dart:convert';
import 'dart:io';

import 'package:proxilife_server/src/auth/auth_middleware.dart';
import 'package:proxilife_server/src/auth/session_service.dart';
import 'package:proxilife_server/src/db/database.dart';
import 'package:proxilife_server/src/repositories/payment_method_repository.dart';
import 'package:proxilife_server/src/repositories/transaction_repository.dart';
import 'package:proxilife_server/src/repositories/user_repository.dart';
import 'package:proxilife_server/src/routes/teledoc_routes.dart';
import 'package:proxilife_server/src/services/payment_service.dart';
import 'package:proxilife_server/src/services/teledoc_payment_gateway.dart';
import 'package:proxilife_server/src/services/teledoc_payment_service_gateway.dart';
import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'teledoc_test_support.dart';

/// Contract tests: the adapter against the REAL PaymentService of the
/// Payment module (in-memory database, Fawzi's code untouched).
void main() {
  late AppDatabase database;
  late PaymentService payments;
  late PaymentServiceTeledocGateway gateway;
  late int patient;
  late int platform;

  setUp(() async {
    database = await AppDatabase.inMemory();
    final db = database.db;
    final users = UserRepository(db);
    payments = PaymentService(
      db: db,
      users: users,
      methods: PaymentMethodRepository(db),
      transactions: TransactionRepository(db),
    );
    patient = await insertTestUser(db, 'patient@test.tn', 'client');
    // Beneficiary account (to agree on with Fawzi): active, with a RIB.
    platform = await insertTestUser(db, 'teledoc@test.tn', 'medecin');
    gateway = PaymentServiceTeledocGateway(
      payments,
      beneficiaryEmail: 'teledoc@test.tn',
    );
  });
  tearDown(() => database.close());

  Future<int> balance(int id) async => (await database.db.query(
        'utilisateur',
        where: 'id = ?',
        whereArgs: [id],
      ))
          .single['solde_centimes'] as int;

  Future<void> addCash() =>
      payments.addMethod(patient, type: PaymentMethodType.especes);

  test('charge : transaction TeleDoc réelle, référence TD-<id>', () async {
    await addCash();
    final id = await gateway.charge(
      patientId: patient,
      amountCents: TeledocPricing.consultationCents,
      requestId: 42,
    );
    expect(id, greaterThan(0));
    final tx = await payments.getTransaction(id, patient, UserRole.client);
    expect(tx.statut, TransactionStatus.paye);
    expect(tx.typeService, ServiceType.teleDoc);
    expect(tx.idReference, 'TD-42');
    expect(tx.montantCentimes, 3000);
    expect(await balance(platform), 3000);
  });

  test('sans moyen de paiement : refus lisible (→ 402)', () async {
    expect(
      () => gateway.charge(patientId: patient, amountCents: 3000, requestId: 1),
      throwsA(isA<TeledocPaymentDeclined>()
          .having((e) => e.message, 'message', contains('moyen de paiement'))),
    );
  });

  test('portefeuille insuffisant : refus', () async {
    await payments.addMethod(patient, type: PaymentMethodType.portefeuille);
    expect(
      () => gateway.charge(patientId: patient, amountCents: 3000, requestId: 1),
      throwsA(isA<TeledocPaymentDeclined>()),
    );
  });

  test('refund : transaction remboursée', () async {
    await addCash();
    final id = await gateway.charge(
        patientId: patient, amountCents: 3000, requestId: 1);
    await gateway.refund(transactionId: id, patientId: patient);
    final tx = await payments.getTransaction(id, patient, UserRole.client);
    expect(tx.statut, TransactionStatus.rembourse);
    expect(await balance(platform), 0);
  });

  test('blocage connu (§7.4) : bénéficiaire sans solde → refus', () async {
    await addCash();
    final id = await gateway.charge(
        patientId: patient, amountCents: 3000, requestId: 1);
    // The beneficiary already cashed out.
    await database.db.update('utilisateur', {'solde_centimes': 0},
        where: 'id = ?', whereArgs: [platform]);
    expect(
      () => gateway.refund(transactionId: id, patientId: patient),
      throwsA(isA<TeledocPaymentDeclined>()),
    );
  });

  test('transaction fictive du mock (id ≤ 0) : rien à rembourser', () async {
    await gateway.refund(transactionId: -7, patientId: patient);
  });

  test('teledocPaymentGateway : mock tant qu\'aucun bénéficiaire n\'est fixé',
      () {
    expect(teledocPaymentGateway(payments), isA<MockTeledocPaymentGateway>());
    expect(teledocPaymentGateway(payments, beneficiaryEmail: '  '),
        isA<MockTeledocPaymentGateway>());
    expect(teledocPaymentGateway(payments, beneficiaryEmail: 'teledoc@test.tn'),
        isA<PaymentServiceTeledocGateway>());
  });

  test('de bout en bout : demande payée puis annulée et remboursée', () async {
    final uploads = await Directory.systemTemp.createTemp('teledoc_pay');
    addTearDown(() => uploads.delete(recursive: true));
    final sessions = SessionService(database.db, UserRepository(database.db));
    final handler = const Pipeline()
        .addMiddleware(requireAuth(sessions))
        .addHandler(buildTeledocModule(database.db,
                payments: gateway, uploadsDir: uploads.path)
            .call);
    final token = await sessions.createSession(patient);
    Future<(int, Map<String, dynamic>)> call(String verb, String path,
        [Object? body]) async {
      final response = await handler(Request(
          verb, Uri.parse('http://test$path'),
          body: body == null ? null : jsonEncode(body),
          headers: {'authorization': 'Bearer $token'}));
      return (
        response.statusCode,
        jsonDecode(await response.readAsString()) as Map<String, dynamic>
      );
    }

    // No payment method yet: not queued.
    final (refused, refusedBody) =
        await call('POST', '/teledoc/requests', validRequestBody());
    expect(refused, 402);
    expect(refusedBody['error'], contains('moyen de paiement'));
    expect(await database.db.query('teledoc_demande'), isEmpty);

    await addCash();
    final (created, request) =
        await call('POST', '/teledoc/requests', validRequestBody());
    expect(created, 201);
    final txId = request['transaction_id'] as int;
    expect(txId, greaterThan(0));

    final (cancelled, _) =
        await call('POST', '/teledoc/requests/${request['id']}/cancel');
    expect(cancelled, 200);
    final tx = await payments.getTransaction(txId, patient, UserRole.client);
    expect(tx.statut, TransactionStatus.rembourse);
  });
}
