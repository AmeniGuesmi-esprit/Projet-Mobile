import 'dart:developer' as developer;

import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../api_error.dart';
import '../repositories/user_repository.dart';
import '../services/payment_service.dart';
import 'coach_qr_service.dart';

/// CoachProche business logic: sessions (coach side), bookings, payment,
/// QR presence check, tracking data and notifications.
///
/// Concurrency model (same as FoodSave):
/// - a seat is taken with ONE conditional `UPDATE coach_seance` inside a
///   sqflite transaction (never read-then-write), so two clients can't take
///   the last seat;
/// - a seat is given back by [_cancelBookingRow], guarded by
///   `statut IN ('en_attente','confirmee')`, so it is released exactly once;
/// - the payment module runs its own transactions, so it is always called
///   OUTSIDE ours (nesting deadlocks sqflite) and serialised by a lock.
class CoachService {
  CoachService({
    required this.db,
    required this.users,
    required this.payments,
    DateTime Function()? clock,
  })  : _clock = clock ?? DateTime.now,
        qr = CoachQrTokenService(db);

  final Database db;
  final UserRepository users;

  /// Existing payment module, reused as-is (type de service: CoachProche).
  final PaymentService payments;
  final CoachQrTokenService qr;
  final DateTime Function() _clock;

  static final Expando<_AsyncLock> _paymentLocks = Expando('coach_payment');
  _AsyncLock get _paymentLock => _paymentLocks[db] ??= _AsyncLock();

  /// Current time in UTC, truncated to the millisecond so that ISO strings
  /// always have the same width (lexical order == chronological order).
  DateTime now() => DateTime.fromMillisecondsSinceEpoch(
      _clock().millisecondsSinceEpoch,
      isUtc: true);

  String nowIso() => _iso(now());

  static String _iso(DateTime d) => DateTime.fromMillisecondsSinceEpoch(
          d.millisecondsSinceEpoch,
          isUtc: true)
      .toIso8601String();

  static DateTime _parse(Object? raw) => DateTime.parse(raw as String).toUtc();

  /// "08/11 à 18h30" (server local time, used in notification texts).
  static String _when(DateTime utc) {
    final l = utc.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)} à ${two(l.hour)}h${two(l.minute)}';
  }

  // =========================================================================
  // Sessions (coach side)
  // =========================================================================

  Future<CoachSessionDto> publish(
      int coachId, Map<String, dynamic> body) async {
    final input = _parseInput(body);
    await _requirePayable(coachId, input.prixCentimes);
    final at = nowIso();
    final id = await db.insert('coach_seance', {
      ...input.toColumns(),
      'places_restantes': input.places,
      'statut': CoachSessionStatus.planifiee.apiValue,
      'coach_id': coachId,
      'cree_le': at,
      'mis_a_jour_le': at,
    });
    return getSession(id, viewerId: coachId);
  }

  /// Full update of a session that has not started yet. Participants are
  /// notified when the date, the place or the duration changes.
  Future<CoachSessionDto> update(
      int coachId, int id, Map<String, dynamic> body) async {
    final row = await _ownSessionRow(coachId, id);
    if (row['statut'] == CoachSessionStatus.annulee.apiValue) {
      throw ApiError.conflict(
          'Cette séance est annulée : elle ne peut plus être modifiée');
    }
    final oldStart = _parse(row['date_heure']);
    if (!oldStart.isAfter(now())) {
      throw ApiError.conflict(
          'Cette séance a déjà commencé : elle ne peut plus être modifiée');
    }
    final input = _parseInput(body);
    final inscrits =
        (row['places_totales'] as int) - (row['places_restantes'] as int);
    if (input.places < inscrits) {
      throw ApiError.conflict(
          '$inscrits participant(s) sont déjà inscrits : le nombre de '
          'places ne peut pas être inférieur');
    }
    if (inscrits > 0 && input.prixCentimes != row['prix_centimes']) {
      throw ApiError.conflict('Le prix ne peut plus être modifié : '
          'des participants ont déjà réservé');
    }
    await _requirePayable(coachId, input.prixCentimes);

    final at = nowIso();
    final changedSchedule = oldStart != input.dateHeure ||
        row['lieu'] != input.lieu ||
        row['duree_minutes'] != input.dureeMinutes;
    final updated = await db.update(
      'coach_seance',
      {
        ...input.toColumns(),
        'places_restantes': input.places - inscrits,
        'mis_a_jour_le': at,
      },
      where: "id = ? AND statut = 'planifiee'",
      whereArgs: [id],
    );
    if (updated != 1) {
      throw ApiError.conflict('Cette séance ne peut plus être modifiée');
    }
    if (changedSchedule && inscrits > 0) {
      final bookings = await db.query('coach_reservation',
          columns: ['id', 'client_id'],
          where: "seance_id = ? AND statut IN ('en_attente','confirmee')",
          whereArgs: [id]);
      for (final b in bookings) {
        await _notify(
          userId: b['client_id'] as int,
          type: CoachNotificationType.seanceModifiee,
          titre: 'Séance modifiée',
          message: 'La séance « ${input.titre} » a été modifiée : elle aura '
              'lieu le ${_when(input.dateHeure)} à ${input.lieu}.',
          cle: 'modifiee:${b['id']}:$at',
          seanceId: id,
          reservationId: b['id'] as int,
        );
      }
    }
    return getSession(id, viewerId: coachId);
  }

  /// Cancels a session that has not started: every active booking is
  /// cancelled, paid ones are refunded when possible, clients are notified.
  Future<CoachSessionDto> cancelSession(int coachId, int id) async {
    final row = await _ownSessionRow(coachId, id);
    if (row['statut'] == CoachSessionStatus.annulee.apiValue) {
      throw ApiError.conflict('Cette séance est déjà annulée');
    }
    if (!_parse(row['date_heure']).isAfter(now())) {
      throw ApiError.conflict(
          'Cette séance a déjà commencé : elle ne peut plus être annulée');
    }
    final changed = await db.update(
      'coach_seance',
      {
        'statut': CoachSessionStatus.annulee.apiValue,
        'mis_a_jour_le': nowIso(),
      },
      where: "id = ? AND statut = 'planifiee'",
      whereArgs: [id],
    );
    if (changed != 1) {
      throw ApiError.conflict('Cette séance est déjà annulée');
    }
    final bookings = await db.query('coach_reservation',
        columns: ['id', 'client_id'],
        where: "seance_id = ? AND statut IN ('en_attente','confirmee')",
        whereArgs: [id],
        orderBy: 'id');
    for (final b in bookings) {
      final bookingId = b['id'] as int;
      if (!await _cancelBookingRow(bookingId, par: 'coach')) continue;
      final refunded = await _refundIfPaid(bookingId);
      final after = await db.query('coach_reservation',
          columns: ['statut_paiement'],
          where: 'id = ?',
          whereArgs: [bookingId]);
      final paymentStatus = after.first['statut_paiement'];
      final refundText = refunded
          ? 'Vous avez été remboursé(e).'
          : paymentStatus == TransactionStatus.paye.apiValue
              ? 'Votre remboursement sera traité dans les plus brefs délais.'
              : 'Aucun montant ne vous a été débité.';
      await _notify(
        userId: b['client_id'] as int,
        type: CoachNotificationType.seanceAnnulee,
        titre: 'Séance annulée',
        message: 'Le coach a annulé la séance « ${row['titre']} » du '
            '${_when(_parse(row['date_heure']))}. $refundText',
        cle: 'seance_annulee:$bookingId',
        seanceId: id,
        reservationId: bookingId,
      );
    }
    return getSession(id, viewerId: coachId);
  }

  /// The coach's own sessions, newest first (planned and cancelled).
  Future<List<CoachSessionDto>> listMine(int coachId) async {
    final rows = await db.rawQuery(
        '$_sessionSelect WHERE s.coach_id = ? '
        'ORDER BY s.date_heure DESC LIMIT 200',
        [coachId]);
    return rows.map((r) => _sessionDto(r)).toList();
  }

  /// The participants of one of the coach's sessions (cancelled bookings
  /// are left out).
  Future<List<CoachBookingDto>> listAttendees(int coachId, int seanceId) async {
    await _ownSessionRow(coachId, seanceId);
    final rows = await db.rawQuery(
        "$_bookingSelect WHERE r.seance_id = ? AND r.statut <> 'annulee' "
        'ORDER BY r.id',
        [seanceId]);
    return _toBookingDtos(rows, viewerId: coachId);
  }

  // =========================================================================
  // Sessions (reads, everyone)
  // =========================================================================

  /// Upcoming planned sessions. Filters: type, level, place (text), a date
  /// range, maximum price; with a position the distance is computed and the
  /// result can be restricted to a radius or sorted by distance.
  Future<List<CoachSessionDto>> search({
    required int viewerId,
    CoachSessionType? type,
    CoachLevel? niveau,
    String? lieu,
    DateTime? from,
    DateTime? to,
    int? prixMaxCentimes,
    double? latitude,
    double? longitude,
    double? rayonKm,
    bool sortByDistance = false,
  }) async {
    final where = StringBuffer("s.statut = 'planifiee' AND s.date_heure > ?");
    final args = <Object?>[nowIso()];
    if (type != null) {
      where.write(' AND s.type = ?');
      args.add(type.apiValue);
    }
    if (niveau != null) {
      where.write(' AND s.niveau = ?');
      args.add(niveau.apiValue);
    }
    final place = lieu?.trim().toLowerCase();
    if (place != null && place.isNotEmpty) {
      where.write(' AND LOWER(s.lieu) LIKE ?');
      args.add('%$place%');
    }
    if (from != null) {
      where.write(' AND s.date_heure >= ?');
      args.add(_iso(from));
    }
    if (to != null) {
      where.write(' AND s.date_heure < ?');
      args.add(_iso(to));
    }
    if (prixMaxCentimes != null) {
      where.write(' AND s.prix_centimes <= ?');
      args.add(prixMaxCentimes);
    }
    final rows = await db.rawQuery(
        '$_sessionSelect WHERE $where ORDER BY s.date_heure ASC LIMIT 300',
        args);
    final booked = await _bookedSessionIds(viewerId);
    var list = rows
        .map((r) =>
            _sessionDto(r, booked: booked, lat: latitude, lng: longitude))
        .toList();
    final radius = rayonKm;
    if (radius != null && latitude != null && longitude != null) {
      list = list.where((s) => (s.distanceKm ?? 0) <= radius).toList();
    }
    if (sortByDistance && latitude != null && longitude != null) {
      list.sort((a, b) => (a.distanceKm ?? double.infinity)
          .compareTo(b.distanceKm ?? double.infinity));
    }
    return list;
  }

  Future<CoachSessionDto> getSession(int id, {required int viewerId}) async {
    final row = await _sessionRow(id);
    if (row == null) throw ApiError.notFound('Séance introuvable');
    return _sessionDto(row, booked: await _bookedSessionIds(viewerId));
  }

  // =========================================================================
  // Bookings (client side)
  // =========================================================================

  /// Books one seat and pays it with [moyenPaiementId] (the caller's default
  /// method when null). Free sessions skip the payment.
  Future<CoachBookingDto> reserve({
    required int clientId,
    required int seanceId,
    int? moyenPaiementId,
  }) async {
    final session = await _sessionRow(seanceId);
    if (session == null) throw ApiError.notFound('Séance introuvable');
    final coachId = session['coach_id'] as int;
    if (coachId == clientId) {
      throw ApiError.forbidden(
          'Vous ne pouvez pas réserver votre propre séance');
    }
    final price = session['prix_centimes'] as int;

    Map<String, Object?>? method;
    Map<String, Object?>? coach;
    if (price > 0) {
      method = await _resolveMethod(clientId, moyenPaiementId);
      coach = await users.findById(coachId);
      if (coach == null ||
          coach['rib'] == null ||
          AccountStatus.parse(coach['statut_compte'] as String) !=
              AccountStatus.actif) {
        throw ApiError.conflict(
            'Ce coach ne peut pas encaisser de paiement pour le moment');
      }
    }

    // 1) Take the seat + create the booking atomically.
    final at = nowIso();
    late int bookingId;
    await db.transaction((txn) async {
      final taken = await txn.rawUpdate(
        'UPDATE coach_seance SET places_restantes = places_restantes - 1, '
        'mis_a_jour_le = ? '
        "WHERE id = ? AND statut = 'planifiee' AND places_restantes >= 1 "
        'AND date_heure > ?',
        [at, seanceId, at],
      );
      if (taken != 1) {
        final rows = await txn
            .query('coach_seance', where: 'id = ?', whereArgs: [seanceId]);
        throw ApiError.conflict(
            _unavailableReason(rows.isEmpty ? null : rows.first, at));
      }
      final duplicate = await txn.query('coach_reservation',
          columns: ['id'],
          where: "seance_id = ? AND client_id = ? AND statut <> 'annulee'",
          whereArgs: [seanceId, clientId]);
      if (duplicate.isNotEmpty) {
        throw ApiError.conflict('Vous avez déjà réservé cette séance');
      }
      bookingId = await txn.insert('coach_reservation', {
        'seance_id': seanceId,
        'client_id': clientId,
        // Free: confirmed right away, with its QR code.
        'statut': price == 0
            ? CoachBookingStatus.confirmee.apiValue
            : CoachBookingStatus.enAttente.apiValue,
        'code_qr_nonce': price == 0 ? CoachQrTokenService.newNonce() : null,
        'montant_centimes': price,
        'mode_paiement': method?['type'],
        'moyen_paiement_id': method?['id'],
        'statut_paiement':
            price == 0 ? null : TransactionStatus.enAttente.apiValue,
        'cree_le': at,
      });
    });

    if (price == 0) {
      await _notifyBooked(bookingId, session);
      return (await getBooking(bookingId, viewerId: clientId))!;
    }

    // 2) Pay, outside the transaction above (PaymentService opens its own).
    TransactionDto? payment;
    String? failure;
    try {
      payment = await _paymentLock.run(() => payments.createTransaction(
            clientId,
            montantCentimes: price,
            beneficiaireEmail: coach!['email'] as String,
            typeService: ServiceType.coachProche,
            idReference: 'CP-RES-$bookingId',
            moyenPaiementId: method!['id'] as int,
          ));
    } on ApiError catch (e) {
      failure = 'Paiement refusé : ${e.message}';
    } catch (e, st) {
      developer.log('Coach payment failure',
          error: e, stackTrace: st, name: 'coach');
      failure = 'Paiement impossible pour le moment. '
          'Aucun montant n\'a été débité, réessayez plus tard.';
    }

    final tx = payment;
    final txStatus = tx == null ? null : await _transactionStatus(tx.id);
    // Card / wallet must be paid now. Cash (payment module rule) stays
    // `en_attente` until the coach confirms receipt at the session.
    final cashPending = txStatus == TransactionStatus.enAttente &&
        method!['type'] == PaymentMethodType.especes.apiValue;
    final paid = txStatus == TransactionStatus.paye || cashPending;
    if (tx == null || txStatus == null || !paid) {
      final message = failure ??
          (method!['type'] == PaymentMethodType.portefeuille.apiValue
              ? 'Paiement refusé : solde insuffisant sur votre portefeuille. '
                  'Rechargez-le ou choisissez un autre moyen de paiement.'
              : 'Paiement refusé par votre moyen de paiement.');
      await db.update(
        'coach_reservation',
        {
          'statut_paiement': TransactionStatus.echoue.apiValue,
          if (tx != null) 'transaction_id': tx.id,
        },
        where: 'id = ?',
        whereArgs: [bookingId],
      );
      await _cancelBookingRow(bookingId, par: 'paiement');
      throw ApiError(402, message);
    }

    // 3) Payment confirmed -> QR code.
    final confirmed = await db.update(
      'coach_reservation',
      {
        'statut': cashPending
            ? CoachBookingStatus.enAttente.apiValue
            : CoachBookingStatus.confirmee.apiValue,
        'statut_paiement': txStatus.apiValue,
        'transaction_id': tx.id,
        'code_qr_nonce': CoachQrTokenService.newNonce(),
      },
      where: "id = ? AND statut = 'en_attente' AND annule_le IS NULL",
      whereArgs: [bookingId],
    );
    if (confirmed != 1) {
      // Cancelled (e.g. by the coach) while the payment was running.
      await db.update(
        'coach_reservation',
        {
          'statut_paiement': txStatus.apiValue,
          'transaction_id': tx.id,
        },
        where: 'id = ?',
        whereArgs: [bookingId],
      );
      await _refundIfPaid(bookingId);
      throw ApiError.conflict('La séance a été annulée pendant votre '
          'paiement. Votre réservation est annulée et le remboursement a '
          'été demandé.');
    }
    await _notifyBooked(bookingId, session);
    return (await getBooking(bookingId, viewerId: clientId))!;
  }

  /// The client's bookings, newest first (with their session).
  Future<List<CoachBookingDto>> listForClient(int clientId) async {
    final rows = await db.rawQuery(
        '$_bookingSelect WHERE r.client_id = ? ORDER BY r.id DESC LIMIT 200',
        [clientId]);
    return _toBookingDtos(rows, viewerId: clientId);
  }

  /// The booking as seen by [viewerId] (its client or the session's coach);
  /// `null` when the viewer has no access (-> 404).
  Future<CoachBookingDto?> getBooking(int bookingId,
      {required int viewerId}) async {
    final row = await _bookingRow(bookingId);
    if (row == null) return null;
    if (row['client_id'] != viewerId && row['s_coach_id'] != viewerId) {
      return null;
    }
    return (await _toBookingDtos([row], viewerId: viewerId)).first;
  }

  Future<CoachBookingDto> cancelBooking(int bookingId,
      {required int clientId}) async {
    final row = await _bookingRow(bookingId);
    if (row == null || row['client_id'] != clientId) {
      throw ApiError.notFound('Réservation introuvable');
    }
    final status = CoachBookingStatus.parse(row['statut'] as String);
    if (!status.isActive) {
      throw ApiError.conflict(status == CoachBookingStatus.present
          ? 'Votre présence a déjà été validée : cette réservation ne peut '
              'plus être annulée'
          : 'Cette réservation est déjà annulée');
    }
    if (!_parse(row['s_date_heure']).isAfter(now())) {
      throw ApiError.conflict(
          'La séance a déjà commencé : l\'annulation n\'est plus possible');
    }
    if (!await _cancelBookingRow(bookingId, par: 'client')) {
      throw ApiError.conflict('Cette réservation n\'est plus active');
    }
    await _refundIfPaid(bookingId);
    await _notify(
      userId: row['s_coach_id'] as int,
      type: CoachNotificationType.reservationAnnulee,
      titre: 'Réservation annulée',
      message: '${row['cl_prenom']} ${row['cl_nom']} a annulé sa place pour '
          '« ${row['s_titre']} » du ${_when(_parse(row['s_date_heure']))}. '
          'La place est de nouveau disponible.',
      cle: 'reservation_annulee:$bookingId',
      seanceId: row['seance_id'] as int,
      reservationId: bookingId,
    );
    return (await getBooking(bookingId, viewerId: clientId))!;
  }

  /// Steps read from the sensor and / or heart rate typed by the client.
  /// Only once the coach validated the presence.
  Future<CoachBookingDto> recordMetrics(
    int bookingId, {
    required int clientId,
    int? pas,
    int? frequenceCardiaque,
  }) async {
    final row = await _bookingRow(bookingId);
    if (row == null || row['client_id'] != clientId) {
      throw ApiError.notFound('Réservation introuvable');
    }
    final error = CoachRules.validateMetrics(
        pas: pas, frequenceCardiaque: frequenceCardiaque);
    if (error != null) throw ApiError.badRequest(error);
    if (row['statut'] != CoachBookingStatus.present.apiValue) {
      throw ApiError.conflict('Le suivi est disponible une fois votre '
          'présence validée par le coach');
    }
    await db.update(
      'coach_reservation',
      {
        if (pas != null) 'pas': pas,
        if (pas != null) 'distance_km': CoachRules.distanceKmFromSteps(pas),
        if (frequenceCardiaque != null)
          'frequence_cardiaque': frequenceCardiaque,
      },
      where: 'id = ?',
      whereArgs: [bookingId],
    );
    return (await getBooking(bookingId, viewerId: clientId))!;
  }

  // =========================================================================
  // Presence check (coach side)
  // =========================================================================

  /// Validates the presence of the client behind [token] (QR code content).
  /// A pending cash payment is confirmed at the same time.
  Future<CoachScanResultDto> scan(int coachId, String token) async {
    final payload = await qr.verify(token);
    if (payload == null) {
      throw ApiError.badRequest('QR code invalide : ce n\'est pas un code '
          'CoachProche');
    }
    final row = await _bookingRow(payload.reservationId);
    if (row == null) throw ApiError.notFound('Réservation introuvable');
    if (row['s_coach_id'] != coachId) {
      throw ApiError.forbidden(
          'Cette réservation concerne la séance d\'un autre coach');
    }
    final status = CoachBookingStatus.parse(row['statut'] as String);
    if (status == CoachBookingStatus.present) {
      final dto = (await getBooking(payload.reservationId, viewerId: coachId))!;
      return CoachScanResultDto(
          reservation: dto, dejaPresent: true, especesEncaissees: false);
    }
    if (status == CoachBookingStatus.annulee) {
      throw ApiError.conflict('Cette réservation a été annulée');
    }
    if (row['code_qr_nonce'] != payload.nonce) {
      throw ApiError.gone('QR code périmé : demandez au client d\'afficher '
          'son QR code actuel');
    }
    final start = _parse(row['s_date_heure']);
    final duree = row['s_duree'] as int;
    if (!CoachRules.isScanWindowOpen(start, duree, now())) {
      throw ApiError.conflict('Hors créneau : la présence se valide de '
          '${CoachRules.scanOpensBefore.inMinutes} minutes avant le début '
          'jusqu\'à la fin de la séance (${_when(start)}).');
    }

    var cashCollected = false;
    final transactionId = row['transaction_id'] as int?;
    if (transactionId != null &&
        await _transactionStatus(transactionId) ==
            TransactionStatus.enAttente) {
      // Cash handed over at the session: the coach confirms receipt.
      await _paymentLock.run(() =>
          payments.confirm(transactionId, coachId, UserRole.coach));
      await db.update(
          'coach_reservation', {'statut_paiement': TransactionStatus.paye.apiValue},
          where: 'id = ?', whereArgs: [payload.reservationId]);
      cashCollected = true;
    }

    final changed = await db.update(
      'coach_reservation',
      {
        'statut': CoachBookingStatus.present.apiValue,
        'present_le': nowIso(),
        'code_qr_nonce': null, // single use
      },
      where: "id = ? AND statut IN ('en_attente','confirmee')",
      whereArgs: [payload.reservationId],
    );
    if (changed != 1) {
      throw ApiError.conflict('Cette réservation n\'est plus active');
    }
    await _notify(
      userId: row['client_id'] as int,
      type: CoachNotificationType.presenceValidee,
      titre: 'Présence validée',
      message: 'Votre présence à « ${row['s_titre']} » est validée. '
          'Bonne séance ! Suivez vos pas et votre fréquence cardiaque dans '
          'l\'application.',
      cle: 'presence_validee:${payload.reservationId}',
      seanceId: row['seance_id'] as int,
      reservationId: payload.reservationId,
    );
    final dto = (await getBooking(payload.reservationId, viewerId: coachId))!;
    return CoachScanResultDto(
        reservation: dto, dejaPresent: false, especesEncaissees: cashCollected);
  }

  // =========================================================================
  // Notifications
  // =========================================================================

  Future<List<CoachNotificationDto>> listNotifications(int userId,
      {bool unreadOnly = false}) async {
    final rows = await db.query(
      'coach_notification',
      where: unreadOnly ? 'utilisateur_id = ? AND lu = 0' : 'utilisateur_id = ?',
      whereArgs: [userId],
      orderBy: 'id DESC',
      limit: 100,
    );
    return rows
        .map((r) => CoachNotificationDto(
              id: r['id'] as int,
              type: CoachNotificationType.parse(r['type'] as String),
              titre: r['titre'] as String,
              message: r['message'] as String,
              seanceId: r['seance_id'] as int?,
              reservationId: r['reservation_id'] as int?,
              lu: r['lu'] == 1,
              creeLe: _parse(r['cree_le']),
            ))
        .toList();
  }

  Future<void> markRead(int userId, {int? id}) async {
    await db.update(
      'coach_notification',
      {'lu': 1},
      where: id == null ? 'utilisateur_id = ?' : 'utilisateur_id = ? AND id = ?',
      whereArgs: id == null ? [userId] : [userId, id],
    );
  }

  /// "Rappel avant la séance": one reminder per booking, sent when the
  /// session starts in less than [CoachRules.reminderLead]. Idempotent
  /// (the event key contains the start date). Returns how many were created.
  Future<int> sendReminders() async {
    final at = nowIso();
    final limit = _iso(now().add(CoachRules.reminderLead));
    final rows = await db.rawQuery(
      'SELECT r.id AS rid, r.client_id, s.id AS sid, s.titre, s.lieu, '
      's.date_heure FROM coach_reservation r '
      'JOIN coach_seance s ON s.id = r.seance_id '
      "WHERE r.statut IN ('en_attente','confirmee') "
      "AND s.statut = 'planifiee' AND s.date_heure > ? AND s.date_heure <= ?",
      [at, limit],
    );
    var created = 0;
    for (final r in rows) {
      final start = _parse(r['date_heure']);
      final ok = await _notify(
        userId: r['client_id'] as int,
        type: CoachNotificationType.rappelSeance,
        titre: 'Votre séance commence bientôt',
        message: '« ${r['titre']} » démarre à ${_when(start)} '
            '(${r['lieu']}). Préparez votre QR code.',
        cle: 'rappel:${r['rid']}:${r['date_heure']}',
        seanceId: r['sid'] as int,
        reservationId: r['rid'] as int,
      );
      if (ok) created++;
    }
    return created;
  }

  // =========================================================================
  // Internals
  // =========================================================================

  static const String _sessionSelect =
      'SELECT s.*, u.prenom AS c_prenom, u.nom AS c_nom '
      'FROM coach_seance s JOIN utilisateur u ON u.id = s.coach_id ';

  static const String _bookingSelect =
      'SELECT r.*, cu.prenom AS cl_prenom, cu.nom AS cl_nom, '
      's.coach_id AS s_coach_id, s.titre AS s_titre, '
      's.date_heure AS s_date_heure, s.duree_minutes AS s_duree, '
      't.facture_numero AS t_facture, t.statut AS t_statut '
      'FROM coach_reservation r '
      'JOIN coach_seance s ON s.id = r.seance_id '
      'JOIN utilisateur cu ON cu.id = r.client_id '
      'LEFT JOIN transaction_ t ON t.id = r.transaction_id ';

  Future<Map<String, Object?>?> _sessionRow(int id) async {
    final rows = await db.rawQuery('$_sessionSelect WHERE s.id = ?', [id]);
    return rows.isEmpty ? null : rows.first;
  }

  /// The session when it belongs to [coachId]; 404 otherwise (a foreign
  /// session is never revealed).
  Future<Map<String, Object?>> _ownSessionRow(int coachId, int id) async {
    final row = await _sessionRow(id);
    if (row == null || row['coach_id'] != coachId) {
      throw ApiError.notFound('Séance introuvable');
    }
    return row;
  }

  Future<Map<String, Object?>?> _bookingRow(int id) async {
    final rows = await db.rawQuery('$_bookingSelect WHERE r.id = ?', [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<Set<int>> _bookedSessionIds(int clientId) async {
    final rows = await db.query('coach_reservation',
        columns: ['seance_id'],
        where: "client_id = ? AND statut <> 'annulee'",
        whereArgs: [clientId]);
    return {for (final r in rows) r['seance_id'] as int};
  }

  CoachSessionDto _sessionDto(
    Map<String, Object?> r, {
    Set<int> booked = const {},
    double? lat,
    double? lng,
  }) {
    final latitude = (r['latitude'] as num).toDouble();
    final longitude = (r['longitude'] as num).toDouble();
    final id = r['id'] as int;
    return CoachSessionDto(
      id: id,
      type: CoachSessionType.parse(r['type'] as String),
      titre: r['titre'] as String,
      description: r['description'] as String?,
      lieu: r['lieu'] as String,
      latitude: latitude,
      longitude: longitude,
      dateHeure: _parse(r['date_heure']),
      dureeMinutes: r['duree_minutes'] as int,
      niveau: CoachLevel.parse(r['niveau'] as String),
      placesTotales: r['places_totales'] as int,
      placesRestantes: r['places_restantes'] as int,
      prixCentimes: r['prix_centimes'] as int,
      statut: CoachSessionStatus.parse(r['statut'] as String),
      coachId: r['coach_id'] as int,
      coachNom: '${r['c_prenom']} ${r['c_nom']}',
      distanceKm: lat == null || lng == null
          ? null
          : (GeoDistance.haversineKm(lat, lng, latitude, longitude) * 10)
                  .round() /
              10,
      dejaReserve: booked.contains(id),
    );
  }

  Future<List<CoachBookingDto>> _toBookingDtos(
    List<Map<String, Object?>> rows, {
    required int viewerId,
  }) async {
    final sessions = <int, CoachSessionDto>{};
    final result = <CoachBookingDto>[];
    for (final r in rows) {
      final seanceId = r['seance_id'] as int;
      var session = sessions[seanceId];
      if (session == null) {
        final sessionRow = await _sessionRow(seanceId);
        if (sessionRow != null) {
          session = _sessionDto(sessionRow);
          sessions[seanceId] = session;
        }
      }
      final id = r['id'] as int;
      final status = CoachBookingStatus.parse(r['statut'] as String);
      final nonce = r['code_qr_nonce'] as String?;
      // The QR token is only handed to the booking's owner.
      final token =
          r['client_id'] == viewerId && status.isActive && nonce != null
              ? await qr.sign(id, nonce)
              : null;
      final paymentStatus =
          (r['t_statut'] ?? r['statut_paiement']) as String?;
      final method = r['mode_paiement'] as String?;
      result.add(CoachBookingDto(
        id: id,
        statut: status,
        seanceId: seanceId,
        seance: session,
        clientId: r['client_id'] as int,
        clientNom: '${r['cl_prenom']} ${r['cl_nom']}',
        codeQr: token,
        montantCentimes: r['montant_centimes'] as int,
        modePaiement: method == null ? null : PaymentMethodType.parse(method),
        statutPaiement:
            paymentStatus == null ? null : TransactionStatus.parse(paymentStatus),
        factureNumero: r['t_facture'] as String?,
        pas: r['pas'] as int?,
        distanceKm: (r['distance_km'] as num?)?.toDouble(),
        frequenceCardiaque: r['frequence_cardiaque'] as int?,
        presentLe: r['present_le'] == null ? null : _parse(r['present_le']),
        creeLe: _parse(r['cree_le']),
      ));
    }
    return result;
  }

  /// Cancels an active booking and gives its seat back. Returns false when
  /// the booking was not active (so the seat is released exactly once).
  Future<bool> _cancelBookingRow(int bookingId, {required String par}) async {
    var released = false;
    final at = nowIso();
    await db.transaction((txn) async {
      final rows = await txn.query('coach_reservation',
          columns: ['seance_id'], where: 'id = ?', whereArgs: [bookingId]);
      if (rows.isEmpty) return;
      final changed = await txn.update(
        'coach_reservation',
        {
          'statut': CoachBookingStatus.annulee.apiValue,
          'annule_le': at,
          'annule_par': par,
          'code_qr_nonce': null,
        },
        where: "id = ? AND statut IN ('en_attente','confirmee')",
        whereArgs: [bookingId],
      );
      if (changed != 1) return;
      released = true;
      await txn.rawUpdate(
        'UPDATE coach_seance SET '
        'places_restantes = MIN(places_totales, places_restantes + 1), '
        'mis_a_jour_le = ? WHERE id = ?',
        [at, rows.first['seance_id']],
      );
    });
    return released;
  }

  /// Refunds the booking's payment when it was paid. A pending cash payment
  /// that was never collected simply fails. Returns true when refunded;
  /// a failed refund (e.g. coach balance too low) is logged and left to be
  /// processed manually.
  Future<bool> _refundIfPaid(int bookingId) async {
    final rows = await db.query('coach_reservation',
        where: 'id = ?', whereArgs: [bookingId]);
    if (rows.isEmpty) return false;
    final row = rows.first;
    final transactionId = row['transaction_id'] as int?;
    if (transactionId == null) return false;
    final status = await _transactionStatus(transactionId);

    if (status == TransactionStatus.enAttente) {
      // Cash never collected: nothing to refund.
      if (TransactionRules.canTransition(
          TransactionStatus.enAttente, TransactionStatus.echoue)) {
        await payments.transactions
            .updateStatus(transactionId, TransactionStatus.echoue);
        await db.update('coach_reservation',
            {'statut_paiement': TransactionStatus.echoue.apiValue},
            where: 'id = ?', whereArgs: [bookingId]);
      }
      return false;
    }
    if (status == TransactionStatus.rembourse) {
      await db.update('coach_reservation',
          {'statut_paiement': TransactionStatus.rembourse.apiValue},
          where: 'id = ?', whereArgs: [bookingId]);
      return true;
    }
    if (status != TransactionStatus.paye) return false;

    final clientId = row['client_id'] as int;
    try {
      await _paymentLock.run(
          () => payments.refund(transactionId, clientId, UserRole.client));
    } on ApiError catch (e) {
      developer.log('Coach refund to process manually: ${e.message}',
          name: 'coach');
      return false;
    } catch (e, st) {
      developer.log('Coach refund failure',
          error: e, stackTrace: st, name: 'coach');
      return false;
    }
    await db.update('coach_reservation',
        {'statut_paiement': TransactionStatus.rembourse.apiValue},
        where: 'id = ?', whereArgs: [bookingId]);
    return true;
  }

  Future<TransactionStatus?> _transactionStatus(int transactionId) async {
    final rows = await db.query('transaction_',
        columns: ['statut'], where: 'id = ?', whereArgs: [transactionId]);
    return rows.isEmpty
        ? null
        : TransactionStatus.parse(rows.first['statut'] as String);
  }

  Future<Map<String, Object?>> _resolveMethod(
      int clientId, int? moyenPaiementId) async {
    final List<Map<String, Object?>> rows;
    if (moyenPaiementId != null) {
      rows = await db.query('moyen_paiement',
          where: 'id = ? AND utilisateur_id = ?',
          whereArgs: [moyenPaiementId, clientId]);
      if (rows.isEmpty) {
        throw ApiError.notFound('Moyen de paiement introuvable');
      }
    } else {
      rows = await db.query('moyen_paiement',
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

  /// A paid session needs a coach able to receive the money (RIB).
  Future<void> _requirePayable(int coachId, int prixCentimes) async {
    if (prixCentimes == 0) return;
    final coach = await users.findById(coachId);
    if (coach == null || coach['rib'] == null) {
      throw ApiError.conflict('Renseignez votre RIB dans votre profil pour '
          'publier une séance payante');
    }
  }

  String _unavailableReason(Map<String, Object?>? row, String nowStr) {
    if (row == null) return 'Séance introuvable';
    if (row['statut'] == CoachSessionStatus.annulee.apiValue) {
      return 'Cette séance a été annulée par le coach';
    }
    if ((row['date_heure'] as String).compareTo(nowStr) <= 0) {
      return 'Cette séance a déjà commencé';
    }
    if ((row['places_restantes'] as int) < 1) {
      return 'Cette séance est complète';
    }
    return 'Cette séance n\'est plus disponible';
  }

  Future<void> _notifyBooked(int bookingId, Map<String, Object?> session) async {
    final rows = await db.query('coach_reservation',
        columns: ['client_id'], where: 'id = ?', whereArgs: [bookingId]);
    if (rows.isEmpty) return;
    final clientId = rows.first['client_id'] as int;
    final start = _parse(session['date_heure']);
    final client = await users.findById(clientId);
    await _notify(
      userId: clientId,
      type: CoachNotificationType.reservationConfirmee,
      titre: 'Réservation confirmée',
      message: 'Votre place pour « ${session['titre']} » le ${_when(start)} '
          'est réservée. Présentez votre QR code au coach.',
      cle: 'reservation_confirmee:$bookingId',
      seanceId: session['id'] as int,
      reservationId: bookingId,
    );
    await _notify(
      userId: session['coach_id'] as int,
      type: CoachNotificationType.nouvelleReservation,
      titre: 'Nouvelle réservation',
      message: '${client?['prenom'] ?? 'Un client'} ${client?['nom'] ?? ''} '
          'a réservé « ${session['titre']} » du ${_when(start)}.',
      cle: 'nouvelle_reservation:$bookingId',
      seanceId: session['id'] as int,
      reservationId: bookingId,
    );
  }

  /// Idempotent per [cle]; returns true when a notification was created.
  Future<bool> _notify({
    required int userId,
    required CoachNotificationType type,
    required String titre,
    required String message,
    required String cle,
    int? seanceId,
    int? reservationId,
  }) async {
    try {
      final id = await db.insert(
        'coach_notification',
        {
          'utilisateur_id': userId,
          'type': type.apiValue,
          'titre': titre,
          'message': message,
          'seance_id': seanceId,
          'reservation_id': reservationId,
          'cle_evenement': cle,
          'lu': 0,
          'cree_le': nowIso(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return id > 0;
    } catch (e, st) {
      // A notification must never break the business operation.
      developer.log('Coach notification failure',
          error: e, stackTrace: st, name: 'coach');
      return false;
    }
  }

  // ----------------------------------------------------------- parsing ----

  _SessionInput _parseInput(Map<String, dynamic> body) {
    String text(String key) {
      final v = body[key];
      return v is String ? v.trim() : '';
    }

    int? whole(String key) {
      final v = body[key];
      if (v is int) return v;
      if (v is String) return int.tryParse(v.trim());
      return null;
    }

    double? real(String key) {
      final v = body[key];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.trim());
      return null;
    }

    final CoachSessionType type;
    final CoachLevel niveau;
    try {
      type = CoachSessionType.parse(text('type'));
    } on ArgumentError {
      throw ApiError.badRequest('Type de séance invalide');
    }
    try {
      niveau = CoachLevel.parse(text('niveau'));
    } on ArgumentError {
      throw ApiError.badRequest('Niveau invalide');
    }
    final date = DateTime.tryParse(text('date_heure'));
    if (date == null) throw ApiError.badRequest('Date de séance invalide');
    final latitude = real('latitude');
    final longitude = real('longitude');
    final duree = whole('duree_minutes');
    final places = whole('places');
    final prix = whole('prix_centimes');
    if (latitude == null || longitude == null) {
      throw ApiError.badRequest('Position GPS invalide : choisissez le lieu '
          'via la recherche d\'adresse');
    }
    if (duree == null) throw ApiError.badRequest('Durée invalide');
    if (places == null) throw ApiError.badRequest('Nombre de places invalide');
    if (prix == null) throw ApiError.badRequest('Prix invalide');

    final description = text('description');
    final input = _SessionInput(
      type: type,
      titre: text('titre'),
      description: description.isEmpty ? null : description,
      lieu: text('lieu'),
      latitude: latitude,
      longitude: longitude,
      dateHeure: DateTime.fromMillisecondsSinceEpoch(
          date.millisecondsSinceEpoch,
          isUtc: true),
      dureeMinutes: duree,
      niveau: niveau,
      places: places,
      prixCentimes: prix,
    );
    final error = CoachRules.validateSession(
      titre: input.titre,
      description: input.description,
      lieu: input.lieu,
      latitude: input.latitude,
      longitude: input.longitude,
      dateHeure: input.dateHeure,
      dureeMinutes: input.dureeMinutes,
      places: input.places,
      prixCentimes: input.prixCentimes,
      now: now(),
    );
    if (error != null) throw ApiError.badRequest(error);
    return input;
  }
}

/// Validated session fields.
class _SessionInput {
  const _SessionInput({
    required this.type,
    required this.titre,
    required this.description,
    required this.lieu,
    required this.latitude,
    required this.longitude,
    required this.dateHeure,
    required this.dureeMinutes,
    required this.niveau,
    required this.places,
    required this.prixCentimes,
  });

  final CoachSessionType type;
  final String titre;
  final String? description;
  final String lieu;
  final double latitude;
  final double longitude;
  final DateTime dateHeure;
  final int dureeMinutes;
  final CoachLevel niveau;
  final int places;
  final int prixCentimes;

  Map<String, Object?> toColumns() => {
        'titre': titre,
        'description': description,
        'type': type.apiValue,
        'lieu': lieu,
        'latitude': latitude,
        'longitude': longitude,
        'date_heure': CoachService._iso(dateHeure),
        'duree_minutes': dureeMinutes,
        'niveau': niveau.apiValue,
        'places_totales': places,
        'prix_centimes': prixCentimes,
      };
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
