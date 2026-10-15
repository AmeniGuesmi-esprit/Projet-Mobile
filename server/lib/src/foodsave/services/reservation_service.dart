import 'dart:async';
import 'dart:developer' as developer;

import 'package:proxilife_shared/proxilife_shared.dart';

import '../../api_error.dart';
import '../../email/reservation_qr_email.dart';
import '../foodsave_context.dart';
import '../foodsave_mappers.dart';
import 'qr_token_service.dart';

/// Reservations, payment, QR tokens, scan and expiry.
///
/// Concurrency model:
/// - units are taken with ONE conditional `UPDATE panier` inside a sqflite
///   transaction (never read-then-write), so concurrent requests can't
///   oversell;
/// - units are given back through [_release], guarded by
///   `quantite_liberee = 0 AND statut = 'en_attente'`, so expiry / cancel /
///   payment failure release them exactly once, whatever the interleaving;
/// - the payment module runs its own transactions, so it is always called
///   OUTSIDE ours (nesting deadlocks sqflite) and serialised by a lock
///   (PaymentService reads balances before its transaction).
class FoodSaveReservationService {
  FoodSaveReservationService(this.ctx) : qr = FoodSaveQrTokenService(ctx);

  final FoodSaveContext ctx;
  final FoodSaveQrTokenService qr;

  /// Max units per reservation.
  static const int maxQuantity = 20;

  /// "Votre QR expire bientôt" is sent when less than this remains.
  static const Duration expiryWarning = Duration(minutes: 10);

  /// A reservation still waiting for its payment after this delay (server
  /// crash mid-payment) is reconciled by [expireDue].
  static const Duration stalePaymentDelay = Duration(minutes: 10);

  static final Expando<_AsyncLock> _paymentLocks = Expando('payment_lock');

  _AsyncLock get _paymentLock =>
      _paymentLocks[ctx.db] ??= _AsyncLock();

  static const String _select =
      'SELECT r.*, t.facture_numero AS t_facture_numero, '
      'u.prenom AS u_prenom, u.nom AS u_nom, '
      'p.commercant_id AS p_commercant_id, p.titre AS p_titre, '
      'p.creneau_retrait_debut AS p_debut, p.creneau_retrait_fin AS p_fin '
      'FROM reservation r JOIN panier p ON p.id = r.panier_id '
      'LEFT JOIN transaction_ t ON t.id = r.transaction_id '
      'LEFT JOIN utilisateur u ON u.id = r.client_id ';

  // -------------------------------------------------------------------------
  // Client: reserve
  // -------------------------------------------------------------------------

  /// Reserves [quantite] units of basket [panierId] and pays them with
  /// [moyenPaiementId] (the caller's default method when null).
  Future<ReservationDto> reserve({
    required int clientId,
    required int panierId,
    required int quantite,
    int? moyenPaiementId,
  }) async {
    if (quantite < 1 || quantite > maxQuantity) {
      throw ApiError.badRequest(
          'La quantité doit être comprise entre 1 et $maxQuantity');
    }

    final basket = await _basketRow(panierId);
    if (basket == null) throw ApiError.notFound('Panier introuvable');
    final merchantId = basket['commercant_id'] as int;
    if (merchantId == clientId) {
      throw ApiError.forbidden(
          'Vous ne pouvez pas réserver votre propre panier');
    }

    final method = await _resolveMethod(clientId, moyenPaiementId);
    final merchant = await ctx.users.findById(merchantId);
    if (merchant == null ||
        merchant['rib'] == null ||
        AccountStatus.parse(merchant['statut_compte'] as String) !=
            AccountStatus.actif) {
      throw ApiError.conflict(
          'Ce commerçant ne peut pas encaisser de paiement pour le moment');
    }

    // 1) Take the units + create the reservation atomically.
    final now = ctx.now();
    final nowIso = now.toIso8601String();
    final minEndIso = now.add(foodSaveMinPickupLead).toIso8601String();
    late int reservationId;
    late int montant;
    await ctx.db.transaction((txn) async {
      final taken = await txn.rawUpdate(
        'UPDATE panier SET quantite = quantite - ?, '
        "statut = CASE WHEN quantite - ? = 0 THEN 'epuise' ELSE statut END, "
        'mis_a_jour_le = ? '
        'WHERE id = ? AND statut = ? AND quantite >= ? '
        'AND date_expiration > ? AND creneau_retrait_fin > ?',
        [
          quantite,
          quantite,
          nowIso,
          panierId,
          BasketStatus.disponible.apiValue,
          quantite,
          nowIso,
          minEndIso,
        ],
      );
      final rows =
          await txn.query('panier', where: 'id = ?', whereArgs: [panierId]);
      if (taken != 1) {
        throw ApiError.conflict(rows.isEmpty
            ? 'Panier introuvable'
            : _unavailableReason(rows.first, quantite, nowIso, minEndIso));
      }
      montant = (rows.first['prix_centimes'] as int) * quantite;
      reservationId = await txn.insert('reservation', {
        'date': nowIso,
        'statut': ReservationStatus.enAttente.apiValue,
        'panier_id': panierId,
        'client_id': clientId,
        'quantite_reservee': quantite,
        'montant_centimes': montant,
        'mode_paiement': method['type'] as String,
        'moyen_paiement_id': method['id'] as int,
        'statut_paiement': TransactionStatus.enAttente.apiValue,
        'quantite_liberee': 0,
        'cree_le': nowIso,
      });
      await ctx.journal.log('reservation_creee',
          utilisateurId: clientId,
          panierId: panierId,
          reservationId: reservationId,
          details: {'quantite': quantite, 'montant_centimes': montant},
          executor: txn);
    });

    // 2) Pay — outside the transaction above (PaymentService opens its own).
    TransactionDto? payment;
    String? failure;
    try {
      payment = await _paymentLock.run(() => ctx.payments.createTransaction(
            clientId,
            montantCentimes: montant,
            beneficiaireEmail: merchant['email'] as String,
            typeService: ServiceType.foodSave,
            idReference: 'FS-RES-$reservationId',
            moyenPaiementId: method['id'] as int,
          ));
    } on ApiError catch (e) {
      failure = 'Paiement refusé : ${e.message}';
    } catch (e, st) {
      developer.log('FoodSave payment failure',
          error: e, stackTrace: st, name: 'foodsave');
      failure = 'Paiement impossible pour le moment. '
          'Aucun montant n\'a été débité, réessayez plus tard.';
    }

    final paid = payment != null && await _transactionIsPaid(payment.id);
    if (!paid) {
      if (payment != null) {
        failure ??= method['type'] == PaymentMethodType.portefeuille.apiValue
            ? 'Paiement refusé : solde insuffisant sur votre portefeuille. '
                'Rechargez-le ou choisissez un autre moyen de paiement.'
            : 'Paiement refusé par votre moyen de paiement.';
      }
      final set = <String, Object?>{
        'statut_paiement': TransactionStatus.echoue.apiValue,
        if (payment != null) 'transaction_id': payment.id,
      };
      final released = await _release(reservationId, ReservationStatus.annule,
          set: set, actorId: clientId, reason: 'paiement_echoue');
      if (!released) {
        // Cancelled concurrently: still record the payment outcome.
        await ctx.db.update('reservation', set,
            where: 'id = ?', whereArgs: [reservationId]);
      }
      await ctx.journal.log('paiement_echoue',
          utilisateurId: clientId,
          panierId: panierId,
          reservationId: reservationId,
          details: {'raison': failure, 'transaction_id': payment?.id});
      throw ApiError(402, failure!);
    }

    // 3) Payment confirmed → QR code.
    final confirmed = await _confirmPayment(reservationId, payment.id);
    if (!confirmed) {
      throw ApiError.conflict(
          'Le panier a été annulé pendant votre paiement. '
          'Votre réservation est annulée et le remboursement a été demandé.');
    }
    return (await getForViewer(reservationId, viewerId: clientId))!;
  }

  // -------------------------------------------------------------------------
  // Reads
  // -------------------------------------------------------------------------

  /// Owner's reservations, newest first (with basket + store).
  Future<List<ReservationDto>> listForClient(int clientId) async {
    await _expireDue(clientId: clientId);
    final rows = await ctx.db.rawQuery(
        '$_select WHERE r.client_id = ? ORDER BY r.id DESC LIMIT 200',
        [clientId]);
    return _toDtos(rows, viewerId: clientId);
  }

  /// Merchant's reservations on its own baskets (no QR token, short name).
  Future<List<ReservationDto>> listForMerchant(
    int merchantId, {
    int? panierId,
    ReservationStatus? statut,
  }) async {
    await _expireDue(merchantId: merchantId);
    final where = StringBuffer('WHERE p.commercant_id = ?');
    final args = <Object?>[merchantId];
    if (panierId != null) {
      where.write(' AND r.panier_id = ?');
      args.add(panierId);
    }
    if (statut != null) {
      where.write(' AND r.statut = ?');
      args.add(statut.apiValue);
    }
    final rows = await ctx.db.rawQuery(
        '$_select $where ORDER BY r.id DESC LIMIT 500', args);
    return _toDtos(rows, viewerId: merchantId);
  }

  /// The reservation as seen by [viewerId] (owner client or the basket's
  /// merchant); `null` when the viewer has no access (→ 404).
  Future<ReservationDto?> getForViewer(int reservationId,
      {required int viewerId}) async {
    var row = await _findRow(reservationId);
    if (row == null) return null;
    if (row['client_id'] != viewerId && row['p_commercant_id'] != viewerId) {
      return null;
    }
    if (await _expireIfDue(row)) row = (await _findRow(reservationId))!;
    return (await _toDtos([row], viewerId: viewerId)).first;
  }

  // -------------------------------------------------------------------------
  // Client: cancel
  // -------------------------------------------------------------------------

  Future<ReservationDto> cancelByClient(int reservationId,
      {required int clientId}) async {
    final row = await _findRow(reservationId);
    if (row == null || row['client_id'] != clientId) {
      throw ApiError.notFound('Réservation introuvable');
    }
    if (await _expireIfDue(row)) {
      throw ApiError.conflict(
          'Cette réservation a expiré : elle ne peut plus être annulée');
    }
    if (row['statut'] != ReservationStatus.enAttente.apiValue) {
      throw ApiError.conflict(
          'Seule une réservation en attente de retrait peut être annulée');
    }
    final released = await _release(reservationId, ReservationStatus.annule,
        actorId: clientId, reason: 'annulation_client');
    if (!released) {
      throw ApiError.conflict(
          'Cette réservation n\'est plus en attente de retrait');
    }
    final refunded = await _refundIfPaid(reservationId);
    await ctx.journal.log('reservation_annulee',
        utilisateurId: clientId,
        panierId: row['panier_id'] as int,
        reservationId: reservationId,
        details: {'par': 'client', 'rembourse': refunded});
    return (await getForViewer(reservationId, viewerId: clientId))!;
  }

  /// Called by the catalog when a merchant cancels a basket: cancels every
  /// active reservation, refunds paid ones when possible, notifies clients.
  /// Returns the number of reservations cancelled.
  Future<int> cancelActiveForBasket(int basketId,
      {required int merchantId}) async {
    final rows = await ctx.db.rawQuery(
      'SELECT r.id, r.client_id, p.titre FROM reservation r '
      'JOIN panier p ON p.id = r.panier_id '
      'WHERE r.panier_id = ? AND p.commercant_id = ? AND r.statut = ? '
      'ORDER BY r.id',
      [basketId, merchantId, ReservationStatus.enAttente.apiValue],
    );
    var count = 0;
    for (final row in rows) {
      final id = row['id'] as int;
      final clientId = row['client_id'] as int;
      final released = await _release(id, ReservationStatus.annule,
          actorId: merchantId, reason: 'panier_annule');
      if (!released) continue;
      count++;
      final refunded = await _refundIfPaid(id);
      final row2 = await ctx.db.query('reservation',
          columns: ['statut_paiement'], where: 'id = ?', whereArgs: [id]);
      final status = row2.first['statut_paiement'];
      final refundText = refunded
          ? 'Vous avez été remboursé(e).'
          : status == TransactionStatus.paye.apiValue
              ? 'Votre remboursement sera traité dans les plus brefs délais.'
              : 'Aucun montant ne vous a été débité.';
      await ctx.notifier.notifyUser(
        userId: clientId,
        type: FoodSaveNotificationType.panierAnnule,
        titre: 'Panier annulé',
        message: 'Le commerçant a annulé ce panier '
            '(« ${row['titre']} »). Votre réservation est annulée. $refundText',
        panierId: basketId,
        reservationId: id,
        cleEvenement: 'panier_annule:$basketId:reservation:$id',
      );
      await ctx.journal.log('reservation_annulee',
          utilisateurId: merchantId,
          panierId: basketId,
          reservationId: id,
          details: {'par': 'commercant', 'rembourse': refunded});
    }
    return count;
  }

  // -------------------------------------------------------------------------
  // Merchant: scan
  // -------------------------------------------------------------------------

  /// Validates a pickup QR. Business refusals are results, never errors.
  Future<ScanResultDto> scan(int merchantId, String token) async {
    final payload = await qr.verify(token);
    if (payload == null) {
      return _refuse(merchantId, null, ScanOutcome.invalide,
          'QR code invalide ou falsifié. Demandez au client d\'afficher '
          'son QR code depuis l\'application.');
    }
    final row = await _findRow(payload.reservationId);
    if (row == null) {
      return _refuse(merchantId, null, ScanOutcome.invalide,
          'QR code invalide : aucune réservation ne correspond.');
    }
    await ctx.journal.log('qr_scanne',
        utilisateurId: merchantId,
        panierId: row['panier_id'] as int,
        reservationId: payload.reservationId);
    if (row['p_commercant_id'] != merchantId) {
      return _refuse(merchantId, payload.reservationId,
          ScanOutcome.autreCommercant,
          'Ce QR code concerne la réservation d\'un autre commerce.');
    }
    return _scanOwned(merchantId, row, payload.nonce, retry: true);
  }

  Future<ScanResultDto> _scanOwned(
      int merchantId, Map<String, Object?> row, String nonce,
      {required bool retry}) async {
    final id = row['id'] as int;
    final terminal = _terminalOutcome(row);
    if (terminal != null) {
      return _refuse(merchantId, id, terminal.$1, terminal.$2,
          row: row);
    }
    if (row['statut_paiement'] != TransactionStatus.paye.apiValue) {
      return _refuse(merchantId, id, ScanOutcome.paiementNonConfirme,
          'Paiement non confirmé : ne remettez pas le panier.',
          row: row);
    }
    final current = row['qr_nonce'] as String?;
    if (current == null || !constantTimeEquals(current, nonce)) {
      return _refuse(merchantId, id, ScanOutcome.invalide,
          'QR code périmé : demandez au client d\'actualiser son QR code.');
    }
    final nowIso = ctx.nowIso();
    final expiry = row['date_expiration_qr'] as String?;
    if (expiry == null || expiry.compareTo(nowIso) <= 0) {
      await _expireIfDue(row);
      final fresh = (await _findRow(id))!;
      return _refuse(merchantId, id, ScanOutcome.expire,
          'QR code expiré : le panier a été remis en vente. '
          'Ne remettez pas le panier.',
          row: fresh);
    }

    final accepted = await ctx.db.rawUpdate(
      'UPDATE reservation SET statut = ?, retire_le = ?, qr_nonce = NULL '
      'WHERE id = ? AND statut = ? AND qr_nonce = ? AND date_expiration_qr > ?',
      [
        ReservationStatus.retire.apiValue,
        nowIso,
        id,
        ReservationStatus.enAttente.apiValue,
        nonce,
        nowIso,
      ],
    );
    if (accepted != 1) {
      // Lost a race (expiry job, cancellation, double scan): re-evaluate.
      final fresh = (await _findRow(id))!;
      if (retry) return _scanOwned(merchantId, fresh, nonce, retry: false);
      return _refuse(merchantId, id, ScanOutcome.invalide,
          'QR code invalide : réessayez.');
    }

    final fresh = (await _findRow(id))!;
    final dto = (await _toDtos([fresh], viewerId: merchantId)).first;
    final quantite = fresh['quantite_reservee'] as int;
    await ctx.journal.log('retrait_valide',
        utilisateurId: merchantId,
        panierId: fresh['panier_id'] as int,
        reservationId: id,
        details: {'quantite': quantite});
    await ctx.notifier.notifyUser(
      userId: fresh['client_id'] as int,
      type: FoodSaveNotificationType.retraitEffectue,
      titre: 'Retrait effectué',
      message: 'Merci ! Vous avez sauvé $quantite '
          'panier${quantite > 1 ? 's' : ''} du gaspillage. Bon appétit !',
      panierId: fresh['panier_id'] as int,
      reservationId: id,
      cleEvenement: 'retrait_effectue:$id',
    );
    final who = dto.clientNom ?? 'votre client';
    return ScanResultDto(
      resultat: ScanOutcome.accepte,
      message: 'Retrait validé : remettez $quantite × ${fresh['p_titre']} '
          'à $who${who.endsWith('.') ? '' : '.'}',
      reservation: dto,
    );
  }

  (ScanOutcome, String)? _terminalOutcome(Map<String, Object?> row) {
    switch (ReservationStatus.parse(row['statut'] as String)) {
      case ReservationStatus.retire:
        return (
          ScanOutcome.dejaUtilise,
          'QR code déjà utilisé : ce panier a déjà été retiré. '
              'Ne le remettez pas une seconde fois.'
        );
      case ReservationStatus.annule:
        return (
          ScanOutcome.annule,
          'Cette réservation a été annulée : ne remettez pas le panier.'
        );
      case ReservationStatus.expire:
        return (
          ScanOutcome.expire,
          'QR code expiré : le panier a été remis en vente. '
              'Ne remettez pas le panier.'
        );
      case ReservationStatus.enAttente:
        return null;
    }
  }

  Future<ScanResultDto> _refuse(int merchantId, int? reservationId,
      ScanOutcome outcome, String message,
      {Map<String, Object?>? row}) async {
    await ctx.journal.log('scan_refuse',
        utilisateurId: merchantId,
        reservationId: reservationId,
        panierId: row?['panier_id'] as int?,
        details: {'resultat': outcome.apiValue});
    return ScanResultDto(
      resultat: outcome,
      message: message,
      reservation:
          row == null ? null : (await _toDtos([row], viewerId: merchantId)).first,
    );
  }

  // -------------------------------------------------------------------------
  // Background jobs
  // -------------------------------------------------------------------------

  /// Background job: active reservations whose QR expired → `expire`, and
  /// their units go back on sale exactly once. Returns how many expired.
  Future<int> expireDue() async {
    await _reconcileStalePayments();
    return _expireDue();
  }

  /// Background job: "votre QR expire bientôt" notifications (once each).
  Future<int> warnExpiringSoon() async {
    final now = ctx.now();
    final rows = await ctx.db.rawQuery(
      'SELECT r.id, r.client_id, r.panier_id, p.titre FROM reservation r '
      'JOIN panier p ON p.id = r.panier_id '
      'WHERE r.statut = ? AND r.statut_paiement = ? '
      'AND r.date_expiration_qr > ? AND r.date_expiration_qr <= ?',
      [
        ReservationStatus.enAttente.apiValue,
        TransactionStatus.paye.apiValue,
        now.toIso8601String(),
        now.add(expiryWarning).toIso8601String(),
      ],
    );
    var count = 0;
    for (final row in rows) {
      final id = row['id'] as int;
      final created = await ctx.notifier.notifyUser(
        userId: row['client_id'] as int,
        type: FoodSaveNotificationType.qrExpireBientot,
        titre: 'Votre QR code expire bientôt',
        message: 'Il vous reste moins de ${expiryWarning.inMinutes} minutes '
            'pour retirer « ${row['titre']} ». Présentez votre QR code au '
            'commerçant.',
        panierId: row['panier_id'] as int,
        reservationId: id,
        cleEvenement: 'qr_expire_bientot:$id',
      );
      if (created) count++;
    }
    return count;
  }

  Future<int> _expireDue({int? clientId, int? merchantId}) async {
    final where = StringBuffer(
        'WHERE r.statut = ? AND r.date_expiration_qr IS NOT NULL '
        'AND r.date_expiration_qr <= ?');
    final args = <Object?>[
      ReservationStatus.enAttente.apiValue,
      ctx.nowIso(),
    ];
    if (clientId != null) {
      where.write(' AND r.client_id = ?');
      args.add(clientId);
    }
    if (merchantId != null) {
      where.write(' AND p.commercant_id = ?');
      args.add(merchantId);
    }
    final rows = await ctx.db.rawQuery('$_select $where', args);
    var count = 0;
    for (final row in rows) {
      if (await _expireIfDue(row)) count++;
    }
    return count;
  }

  /// Expires [row] when its QR is past due. Returns true when THIS call
  /// expired it (units released + client notified).
  Future<bool> _expireIfDue(Map<String, Object?> row) async {
    if (row['statut'] != ReservationStatus.enAttente.apiValue) return false;
    final expiry = row['date_expiration_qr'] as String?;
    if (expiry == null || expiry.compareTo(ctx.nowIso()) > 0) return false;
    final id = row['id'] as int;
    final released = await _release(id, ReservationStatus.expire,
        onlyIfQrExpired: true, reason: 'qr_expire');
    if (!released) return false;
    await ctx.journal.log('reservation_expiree',
        utilisateurId: row['client_id'] as int,
        panierId: row['panier_id'] as int,
        reservationId: id);
    await ctx.notifier.notifyUser(
      userId: row['client_id'] as int,
      type: FoodSaveNotificationType.reservationExpiree,
      titre: 'Réservation expirée',
      message: 'Votre QR code a expiré : le panier a été remis en vente. '
          'Aucun remboursement automatique n\'est effectué ; contactez le '
          'commerçant si besoin.',
      panierId: row['panier_id'] as int,
      reservationId: id,
      cleEvenement: 'reservation_expiree:$id',
    );
    return true;
  }

  /// Reservations stuck in "payment in progress" (server stopped during the
  /// payment): honour a payment that went through, otherwise cancel them so
  /// their units go back on sale.
  Future<void> _reconcileStalePayments() async {
    final limit =
        ctx.now().subtract(stalePaymentDelay).toIso8601String();
    final rows = await ctx.db.query('reservation',
        columns: ['id', 'client_id'],
        where: 'statut = ? AND statut_paiement = ? AND cree_le <= ?',
        whereArgs: [
          ReservationStatus.enAttente.apiValue,
          TransactionStatus.enAttente.apiValue,
          limit,
        ]);
    for (final row in rows) {
      final id = row['id'] as int;
      final tx = await ctx.db.query('transaction_',
          columns: ['id', 'statut'],
          where: 'id_reference = ? AND type_service = ?',
          whereArgs: ['FS-RES-$id', ServiceType.foodSave.apiValue],
          orderBy: 'id DESC',
          limit: 1);
      if (tx.isNotEmpty && tx.first['statut'] == TransactionStatus.paye.apiValue) {
        await _confirmPayment(id, tx.first['id'] as int);
      } else {
        await _release(id, ReservationStatus.annule,
            set: {
              'statut_paiement': TransactionStatus.echoue.apiValue,
              if (tx.isNotEmpty) 'transaction_id': tx.first['id'] as int,
            },
            reason: 'paiement_non_finalise');
      }
    }
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  /// Release rule: moves an active reservation to [to] and gives its units
  /// back to the basket, exactly once (guarded by `quantite_liberee = 0`).
  /// A sold-out basket becomes available again; terminal baskets keep their
  /// status. Returns true when this call performed the release.
  Future<bool> _release(
    int reservationId,
    ReservationStatus to, {
    Map<String, Object?> set = const {},
    bool onlyIfQrExpired = false,
    int? actorId,
    required String reason,
  }) async {
    final nowIso = ctx.nowIso();
    var released = false;
    await ctx.db.transaction((txn) async {
      final rows = await txn.query('reservation',
          columns: ['panier_id', 'quantite_reservee', 'client_id'],
          where: 'id = ?',
          whereArgs: [reservationId]);
      if (rows.isEmpty) return;
      final panierId = rows.first['panier_id'] as int;
      final quantity = rows.first['quantite_reservee'] as int;

      final sql = StringBuffer('UPDATE reservation SET statut = ?, '
          'qr_nonce = NULL, quantite_liberee = quantite_reservee');
      final args = <Object?>[to.apiValue];
      set.forEach((column, value) {
        sql.write(', $column = ?');
        args.add(value);
      });
      sql.write(' WHERE id = ? AND statut = ? AND quantite_liberee = 0');
      args.addAll([reservationId, ReservationStatus.enAttente.apiValue]);
      if (onlyIfQrExpired) {
        sql.write(' AND date_expiration_qr IS NOT NULL '
            'AND date_expiration_qr <= ?');
        args.add(nowIso);
      }
      if (await txn.rawUpdate(sql.toString(), args) != 1) return;

      // Units always go back to the stock; a sold-out basket is put back on
      // sale only while it has not expired (the expiry job handles the rest).
      await txn.rawUpdate(
        'UPDATE panier SET quantite = quantite + ?, '
        "statut = CASE WHEN statut = 'epuise' AND date_expiration > ? "
        "THEN 'disponible' ELSE statut END, "
        'mis_a_jour_le = ? WHERE id = ?',
        [quantity, nowIso, nowIso, panierId],
      );
      await ctx.journal.log('quantite_liberee',
          utilisateurId: actorId ?? rows.first['client_id'] as int,
          panierId: panierId,
          reservationId: reservationId,
          details: {
            'quantite': quantity,
            'statut': to.apiValue,
            'raison': reason,
          },
          executor: txn);
      released = true;
    });
    return released;
  }

  /// Marks the reservation paid and issues its QR code. Returns false when
  /// the reservation was cancelled meanwhile (the payment is then refunded).
  Future<bool> _confirmPayment(int reservationId, int transactionId) async {
    final row = (await _findRow(reservationId))!;
    final now = ctx.now();
    final expiry = FoodSaveRules.qrExpiry(
      now: now,
      pickupStart: DateTime.parse(row['p_debut'] as String),
      pickupEnd: DateTime.parse(row['p_fin'] as String),
      ttl: ctx.qrTtl,
    );
    final updated = await ctx.db.update(
      'reservation',
      {
        'statut_paiement': TransactionStatus.paye.apiValue,
        'transaction_id': transactionId,
        'qr_nonce': FoodSaveQrTokenService.newNonce(),
        'date_creation_qr': now.toIso8601String(),
        'date_expiration_qr': expiry.toUtc().toIso8601String(),
      },
      where: 'id = ? AND statut = ? AND statut_paiement = ?',
      whereArgs: [
        reservationId,
        ReservationStatus.enAttente.apiValue,
        TransactionStatus.enAttente.apiValue,
      ],
    );
    final clientId = row['client_id'] as int;
    final panierId = row['panier_id'] as int;
    if (updated != 1) {
      // Cancelled while paying: record the payment, then give it back.
      await ctx.db.update(
        'reservation',
        {
          'statut_paiement': TransactionStatus.paye.apiValue,
          'transaction_id': transactionId,
        },
        where: 'id = ? AND statut_paiement = ?',
        whereArgs: [reservationId, TransactionStatus.enAttente.apiValue],
      );
      await _refundIfPaid(reservationId);
      return false;
    }
    await ctx.journal.log('qr_genere',
        utilisateurId: clientId,
        panierId: panierId,
        reservationId: reservationId,
        details: {
          'transaction_id': transactionId,
          'expire_le': expiry.toUtc().toIso8601String(),
        });
    await ctx.notifier.notifyUser(
      userId: clientId,
      type: FoodSaveNotificationType.reservationConfirmee,
      titre: 'Réservation confirmée',
      message: 'Votre panier « ${row['p_titre']} » est réservé et payé. '
          'Présentez votre QR code au commerçant pendant le créneau de '
          'retrait.',
      panierId: panierId,
      reservationId: reservationId,
      cleEvenement: 'reservation_confirmee:$reservationId',
    );
    // Never delays nor fails the reservation: SMTP errors are only logged.
    unawaited(_emailQr(reservationId));
    return true;
  }

  /// Sends the pickup QR code by e-mail to the client (if a mailer is set).
  Future<void> _emailQr(int reservationId) async {
    final mailer = ctx.mailer;
    if (mailer == null) return;
    try {
      final rows = await ctx.db.rawQuery(
        'SELECT r.id, r.quantite_reservee, r.montant_centimes, r.qr_nonce, '
        'r.mode_paiement, '
        'r.date_expiration_qr, u.email, u.prenom, p.titre, '
        'p.creneau_retrait_debut, p.creneau_retrait_fin, '
        'c.nom AS c_nom, c.adresse AS c_adresse '
        'FROM reservation r JOIN panier p ON p.id = r.panier_id '
        'JOIN utilisateur u ON u.id = r.client_id '
        'LEFT JOIN commerce c ON c.commercant_id = p.commercant_id '
        'WHERE r.id = ?',
        [reservationId],
      );
      if (rows.isEmpty) return;
      final row = rows.first;
      final nonce = row['qr_nonce'] as String?;
      final expiry = row['date_expiration_qr'] as String?;
      if (nonce == null || expiry == null) return;
      await mailer.sendReservationQr(ReservationQrEmail(
        to: row['email'] as String,
        prenom: row['prenom'] as String,
        reservationId: reservationId,
        basketTitle: row['titre'] as String,
        storeName: row['c_nom'] as String? ?? 'Commerce FoodSave',
        storeAddress: row['c_adresse'] as String? ?? '',
        quantity: row['quantite_reservee'] as int,
        amountCents: row['montant_centimes'] as int,
        pickupStart: DateTime.parse(row['creneau_retrait_debut'] as String),
        pickupEnd: DateTime.parse(row['creneau_retrait_fin'] as String),
        qrExpiry: DateTime.parse(expiry),
        qrToken: await qr.sign(reservationId, nonce),
        cashAtPickup:
            row['mode_paiement'] == PaymentMethodType.especes.apiValue,
      ));
      await ctx.journal.log('qr_envoye_email', reservationId: reservationId);
    } catch (e, st) {
      developer.log('QR e-mail failed for reservation $reservationId',
          error: e, stackTrace: st, name: 'foodsave');
    }
  }

  /// Refunds a paid reservation through the payment module. On failure the
  /// reservation stays `paye` and the case is logged for manual handling.
  Future<bool> _refundIfPaid(int reservationId) async {
    final rows = await ctx.db.query('reservation',
        where: 'id = ?', whereArgs: [reservationId]);
    if (rows.isEmpty) return false;
    final row = rows.first;
    final transactionId = row['transaction_id'] as int?;
    if (row['statut_paiement'] != TransactionStatus.paye.apiValue ||
        transactionId == null) {
      return false;
    }
    final clientId = row['client_id'] as int;
    String? error;
    try {
      await _paymentLock.run(() =>
          ctx.payments.refund(transactionId, clientId, UserRole.client));
    } on ApiError catch (e) {
      error = e.message;
    } catch (e, st) {
      developer.log('FoodSave refund failure',
          error: e, stackTrace: st, name: 'foodsave');
      error = 'Erreur interne';
    }
    if (error != null) {
      await ctx.journal.log('remboursement_a_traiter',
          utilisateurId: clientId,
          panierId: row['panier_id'] as int,
          reservationId: reservationId,
          details: {'transaction_id': transactionId, 'raison': error});
      return false;
    }
    await ctx.db.update('reservation',
        {'statut_paiement': TransactionStatus.rembourse.apiValue},
        where: 'id = ?', whereArgs: [reservationId]);
    await ctx.journal.log('remboursement_effectue',
        utilisateurId: clientId,
        panierId: row['panier_id'] as int,
        reservationId: reservationId,
        details: {'transaction_id': transactionId});
    return true;
  }

  Future<bool> _transactionIsPaid(int transactionId) async {
    final rows = await ctx.db.query('transaction_',
        columns: ['statut'], where: 'id = ?', whereArgs: [transactionId]);
    return rows.isNotEmpty &&
        rows.first['statut'] == TransactionStatus.paye.apiValue;
  }

  Future<Map<String, Object?>> _resolveMethod(
      int clientId, int? moyenPaiementId) async {
    final List<Map<String, Object?>> rows;
    if (moyenPaiementId != null) {
      rows = await ctx.db.query('moyen_paiement',
          where: 'id = ? AND utilisateur_id = ?',
          whereArgs: [moyenPaiementId, clientId]);
      if (rows.isEmpty) {
        throw ApiError.notFound('Moyen de paiement introuvable');
      }
    } else {
      rows = await ctx.db.query('moyen_paiement',
          where: 'utilisateur_id = ?',
          whereArgs: [clientId],
          orderBy: 'par_defaut DESC, id DESC',
          limit: 1);
      if (rows.isEmpty) {
        throw ApiError.badRequest('Ajoutez d\'abord un moyen de paiement');
      }
    }
    final method = rows.first;
    if (method['type'] == PaymentMethodType.carteBancaire.apiValue) {
      final expiry = method['date_expiration'] as String?;
      if (expiry == null || !isValidCardExpiry(expiry)) {
        throw ApiError.badRequest('La carte sélectionnée est expirée');
      }
    }
    return method;
  }

  String _unavailableReason(Map<String, Object?> basket, int quantity,
      String nowIso, String minEndIso) {
    final status = BasketStatus.parse(basket['statut'] as String);
    final available = basket['quantite'] as int;
    if (status == BasketStatus.annule) {
      return 'Ce panier a été annulé par le commerçant';
    }
    if (status == BasketStatus.expire ||
        (basket['date_expiration'] as String).compareTo(nowIso) <= 0) {
      return 'Ce panier a expiré';
    }
    if ((basket['creneau_retrait_fin'] as String).compareTo(minEndIso) <= 0) {
      return 'Le créneau de retrait est terminé ou se termine dans moins de '
          '${foodSaveMinPickupLead.inMinutes} minutes';
    }
    if (status == BasketStatus.epuise || available <= 0) {
      return 'Ce panier est épuisé';
    }
    if (available < quantity) {
      return 'Quantité insuffisante : il ne reste que $available '
          'panier${available > 1 ? 's' : ''}';
    }
    return 'Ce panier n\'est plus disponible';
  }

  Future<Map<String, Object?>?> _basketRow(int id) async {
    final rows =
        await ctx.db.query('panier', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, Object?>?> _findRow(int reservationId) async {
    final rows =
        await ctx.db.rawQuery('$_select WHERE r.id = ?', [reservationId]);
    return rows.isEmpty ? null : rows.first;
  }

  /// Rows (from [_select]) → DTOs as seen by [viewerId]: the owner gets the
  /// QR token of an active paid reservation, the merchant gets the client's
  /// short name and never the token.
  Future<List<ReservationDto>> _toDtos(List<Map<String, Object?>> rows,
      {required int viewerId}) async {
    if (rows.isEmpty) return const [];
    final basketIds = rows.map((r) => r['panier_id'] as int).toSet().toList();
    final baskets = await ctx.db.query('panier',
        where: 'id IN (${List.filled(basketIds.length, '?').join(',')})',
        whereArgs: basketIds);
    final merchantIds =
        baskets.map((b) => b['commercant_id'] as int).toSet().toList();
    final stores = await ctx.db.query('commerce',
        where:
            'commercant_id IN (${List.filled(merchantIds.length, '?').join(',')})',
        whereArgs: merchantIds);
    final storeByMerchant = {
      for (final s in stores) s['commercant_id'] as int: storeFromRow(s),
    };
    final basketById = {
      for (final b in baskets)
        b['id'] as int: basketFromRow(b,
            store: storeByMerchant[b['commercant_id'] as int]),
    };

    final result = <ReservationDto>[];
    for (final row in rows) {
      final isOwner = row['client_id'] == viewerId;
      final isMerchant = row['p_commercant_id'] == viewerId;
      final nonce = row['qr_nonce'] as String?;
      final showQr = isOwner &&
          nonce != null &&
          row['statut'] == ReservationStatus.enAttente.apiValue &&
          row['statut_paiement'] == TransactionStatus.paye.apiValue;
      result.add(reservationFromRow(
        row,
        panier: basketById[row['panier_id'] as int],
        qrToken: showQr ? await qr.sign(row['id'] as int, nonce) : null,
        clientNom: isMerchant && !isOwner
            ? shortName((row['u_prenom'] as String?) ?? 'Client',
                (row['u_nom'] as String?) ?? '')
            : null,
        factureNumero: isOwner ? row['t_facture_numero'] as String? : null,
      ));
    }
    return result;
  }
}

/// Minimal FIFO async mutex.
class _AsyncLock {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}
