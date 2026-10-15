import 'dart:io';
import 'dart:typed_data';

import 'package:proxilife_server/src/db/database.dart';
import 'package:proxilife_server/src/email/email_sender.dart';
import 'package:proxilife_server/src/email/qr_png.dart';
import 'package:proxilife_server/src/email/reservation_qr_email.dart';
import 'package:proxilife_server/src/foodsave/foodsave_context.dart';
import 'package:proxilife_server/src/foodsave/foodsave_schema.dart';
import 'package:proxilife_server/src/foodsave/services/reservation_service.dart';
import 'package:proxilife_server/src/repositories/payment_method_repository.dart';
import 'package:proxilife_server/src/repositories/transaction_repository.dart';
import 'package:proxilife_server/src/repositories/user_repository.dart';
import 'package:proxilife_server/src/services/payment_service.dart';
import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:test/test.dart';

class _RecordingMailer implements ReservationMailer {
  final List<ReservationQrEmail> sent = [];
  bool fail = false;

  @override
  Future<void> sendReservationQr(ReservationQrEmail email) async {
    if (fail) throw const SocketException('SMTP indisponible');
    sent.add(email);
  }
}

void main() {
  group('encodeQrPng', () {
    test('valid PNG, quiet zone white, finder pattern dark', () {
      final png = encodeQrPng('FS1.42.abc', scale: 4, margin: 4);
      expect(
          png.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

      final data = ByteData.sublistView(png);
      expect(String.fromCharCodes(png.sublist(12, 16)), 'IHDR');
      final width = data.getUint32(16);
      expect(width, data.getUint32(20));
      // Version 1 (21 modules) + 2 × 4 quiet modules, 4 px each.
      expect(width, (21 + 8) * 4);

      final idatLength = data.getUint32(33);
      expect(String.fromCharCodes(png.sublist(37, 41)), 'IDAT');
      final raw = ZLibCodec().decode(png.sublist(41, 41 + idatLength));
      int pixel(int x, int y) => raw[y * (width + 1) + 1 + x];
      expect(pixel(0, 0), 0xFF);
      expect(pixel(16, 16), 0x00); // top-left finder corner
    });
  });

  group('reservation QR e-mail', () {
    late AppDatabase database;
    late _RecordingMailer mailer;
    late FoodSaveReservationService service;
    late int clientId;
    late int basketId;
    late int methodId;
    final now = DateTime.utc(2026, 10, 13, 9);

    setUp(() async {
      database = await AppDatabase.inMemory();
      final db = database.db;
      final hasFoodSave = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'panier'");
      if (hasFoodSave.isEmpty) await createFoodSaveSchema(db);
      final users = UserRepository(db);
      final payments = PaymentService(
        db: db,
        users: users,
        methods: PaymentMethodRepository(db),
        transactions: TransactionRepository(db),
      );
      mailer = _RecordingMailer();
      service = FoodSaveReservationService(FoodSaveContext(
        db: db,
        users: users,
        payments: payments,
        uploadsDir: 'build/test_uploads',
        mailer: mailer,
        clock: () => now,
      ));

      Future<int> user(String email, String role) => db.insert('utilisateur', {
            'nom': 'Guesmi',
            'prenom': 'Ameni',
            'email': email,
            'telephone': '0612345678',
            'mot_de_passe_hash': 'x',
            'role': role,
            'statut_compte': 'actif',
            'rib': role == 'client' ? null : '30004000011234567890173',
            'solde_centimes': 0,
            'cree_le': now.toIso8601String(),
          });
      final merchantId = await user('commerce@test.fr', 'commercant');
      clientId = await user('client@test.fr', 'client');
      await db.insert('commerce', {
        'commercant_id': merchantId,
        'nom': 'Boulangerie <Ennour>',
        'adresse': '1 rue de Tunis',
        'latitude': 36.8,
        'longitude': 10.18,
        'categorie': 'boulangerie',
        'cree_le': now.toIso8601String(),
        'mis_a_jour_le': now.toIso8601String(),
      });
      basketId = await db.insert('panier', {
        'titre': 'Panier <b>du soir</b>',
        'contenu': 'Pains',
        'categorie': 'boulangerie',
        'prix_centimes': 450,
        'prix_initial_centimes': 1350,
        'quantite': 3,
        'quantite_initiale': 3,
        'creneau_retrait_debut':
            now.add(const Duration(hours: 1)).toIso8601String(),
        'creneau_retrait_fin':
            now.add(const Duration(hours: 3)).toIso8601String(),
        'date_expiration': now.add(const Duration(hours: 4)).toIso8601String(),
        'statut': 'disponible',
        'commercant_id': merchantId,
        'cree_le': now.toIso8601String(),
        'mis_a_jour_le': now.toIso8601String(),
      });
      methodId =
          (await payments.addMethod(clientId, type: PaymentMethodType.especes))
              .id;
    });

    tearDown(() async => database.close());

    Future<void> settle() async {
      for (var i = 0; i < 50 && mailer.sent.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test('paid reservation → e-mail with the same QR token', () async {
      final dto = await service.reserve(
          clientId: clientId,
          panierId: basketId,
          quantite: 2,
          moyenPaiementId: methodId);
      await settle();

      final email = mailer.sent.single;
      expect(email.to, 'client@test.fr');
      expect(email.qrToken, dto.qrToken);
      expect(email.reference, 'FS-${dto.id}');
      expect(email.amountLabel, '9,000 DT');
      expect(email.quantityLabel, '2 paniers');
      // Cash: paid at pickup, never "payée".
      expect(email.cashAtPickup, isTrue);
      expect(email.html, contains('paiement en espèces au retrait'));
      expect(email.html, contains('À payer au retrait'));
      expect(email.text, isNot(contains('payée')));
      expect(email.html, contains('cid:$reservationQrCid'));
      // Merchant-controlled text is escaped.
      expect(email.html, contains('Panier &lt;b&gt;du soir'));
      expect(email.html, contains('Boulangerie &lt;Ennour&gt;'));
      expect(email.html, isNot(contains('<b>du soir</b>')));
    });

    test('an SMTP failure never fails the reservation', () async {
      mailer.fail = true;
      final dto = await service.reserve(
          clientId: clientId,
          panierId: basketId,
          quantite: 1,
          moyenPaiementId: methodId);
      expect(dto.statutPaiement, TransactionStatus.paye);
      expect(dto.qrToken, isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(mailer.sent, isEmpty);
    });
  });
}
