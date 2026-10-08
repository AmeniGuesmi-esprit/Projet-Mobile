import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../api_error.dart';
import '../repositories/payment_method_repository.dart';
import '../repositories/transaction_repository.dart';
import '../repositories/user_repository.dart';

/// Business rules for payment methods and internal transactions.
///
/// Semantics per payment method type:
/// - carte_bancaire / especes : simulated, immediate success (`paye`).
/// - portefeuille : debits the payer's internal wallet; insufficient balance
///   yields a `echoue` transaction.
/// On any `paye` transaction the beneficiary's wallet is credited (they would
/// later cash out to their RIB).
class PaymentService {
  PaymentService({
    required Database db,
    required this.users,
    required this.methods,
    required this.transactions,
  }) : _db = db;

  final Database _db;
  final UserRepository users;
  final PaymentMethodRepository methods;
  final TransactionRepository transactions;

  // -------------------------------------------------------------------------
  // Payment methods CRUD
  // -------------------------------------------------------------------------

  Future<List<PaymentMethodDto>> listMethods(int utilisateurId) async {
    final rows = await methods.listForUser(utilisateurId);
    return rows.map(methods.toDto).toList();
  }

  Future<PaymentMethodDto> addMethod(
    int utilisateurId, {
    required PaymentMethodType type,
    String? numeroCarte,
    String? nomTitulaire,
    String? dateExpiration,
    bool parDefaut = false,
  }) async {
    String? last4;
    String? titulaire;
    String? expiration;

    if (type == PaymentMethodType.carteBancaire) {
      final numero = numeroCarte ?? '';
      if (!isValidCardNumber(numero)) {
        throw ApiError.badRequest('Numéro de carte invalide');
      }
      if (dateExpiration == null || !isValidCardExpiry(dateExpiration)) {
        throw ApiError.badRequest('Date d\'expiration invalide ou dépassée');
      }
      expiration = dateExpiration;
      titulaire = nomTitulaire?.trim();
      if (titulaire == null || titulaire.length < 2) {
        throw ApiError.badRequest('Nom du titulaire requis');
      }
      last4 = last4OfCard(numero);
    }

    // The very first method is automatically the default one.
    final hasNone = await methods.countForUser(utilisateurId) == 0;
    final id = await methods.insert(
      utilisateurId: utilisateurId,
      type: type,
      last4: last4,
      titulaire: titulaire?.toUpperCase(),
      dateExpiration: expiration,
      parDefaut: parDefaut || hasNone,
    );

    final row = await methods.findById(id);
    return methods.toDto(row!);
  }

  Future<PaymentMethodDto> updateMethod(
    int utilisateurId,
    int methodId, {
    String? nomTitulaire,
    String? dateExpiration,
  }) async {
    final row = await _ownMethod(utilisateurId, methodId);
    if (dateExpiration != null) {
      if (PaymentMethodType.parse(row['type'] as String) ==
              PaymentMethodType.carteBancaire &&
          !isValidCardExpiry(dateExpiration)) {
        throw ApiError.badRequest('Date d\'expiration invalide ou dépassée');
      }
    }
    await methods.update(methodId,
        nomTitulaire: nomTitulaire?.trim(), dateExpiration: dateExpiration);
    final updated = await methods.findById(methodId);
    return methods.toDto(updated!);
  }

  /// Cancelling / refunding pending transactions that use this method is the
  /// user's responsibility; deletion of a method is always allowed.
  Future<void> deleteMethod(int utilisateurId, int methodId) async {
    final row = await _ownMethod(utilisateurId, methodId);
    await methods.delete(row['id'] as int);

    // Reassign the default flag if needed.
    final remaining = await methods.listForUser(utilisateurId);
    if (remaining.isNotEmpty &&
        !remaining.any((m) => (m['par_defaut'] as int) == 1)) {
      await methods.setDefault(remaining.first['id'] as int, utilisateurId);
    }
  }

  Future<void> setDefaultMethod(int utilisateurId, int methodId) async {
    await _ownMethod(utilisateurId, methodId);
    await methods.setDefault(methodId, utilisateurId);
  }

  // -------------------------------------------------------------------------
  // Transactions
  // -------------------------------------------------------------------------

  Future<List<TransactionDto>> listTransactions(
    int utilisateurId, {
    TransactionStatus? statut,
    ServiceType? service,
  }) async {
    final rows = await transactions.listForUser(
      utilisateurId,
      statut: statut,
      service: service,
    );
    return rows.map(transactions.toDto).toList();
  }

  Future<TransactionDto> createTransaction(
    int payerId, {
    required int montantCentimes,
    required String beneficiaireEmail,
    required ServiceType typeService,
    String? idReference,
    int? moyenPaiementId,
  }) async {
    if (!isValidAmountCents(montantCentimes)) {
      throw ApiError.badRequest('Montant invalide');
    }

    final payer = await users.findById(payerId);
    if (payer == null) throw ApiError.notFound('Compte introuvable');

    final beneficiaire =
        await users.findByEmail(beneficiaireEmail);
    if (beneficiaire == null) {
      throw ApiError.notFound('Bénéficiaire introuvable');
    }
    final beneficiaireRole =
        UserRole.parse(beneficiaire['role'] as String);
    if (!beneficiaireRole.canReceivePayments) {
      throw ApiError.badRequest(
          'Le bénéficiaire doit être un professionnel');
    }
    if ((beneficiaire['rib'] as String?) == null) {
      throw ApiError.badRequest(
          'Le bénéficiaire n\'a pas de RIB enregistré');
    }
    if (AccountStatus.parse(beneficiaire['statut_compte'] as String) !=
        AccountStatus.actif) {
      throw ApiError.badRequest('Le bénéficiaire n\'est pas actif');
    }
    if ((beneficiaire['id'] as int) == payerId) {
      throw ApiError.badRequest(
          'Vous ne pouvez pas vous payer vous-même');
    }

    Map<String, Object?>? methodRow;
    if (moyenPaiementId != null) {
      methodRow = await methods.findById(moyenPaiementId);
      if (methodRow == null ||
          methodRow['utilisateur_id'] != payerId) {
        throw ApiError.notFound('Moyen de paiement introuvable');
      }
      final type = PaymentMethodType.parse(methodRow['type'] as String);
      if (type == PaymentMethodType.carteBancaire) {
        final expiry = methodRow['date_expiration'] as String?;
        if (expiry == null || !isValidCardExpiry(expiry)) {
          throw ApiError.badRequest(
              'La carte sélectionnée est expirée');
        }
      }
    } else {
      // Fallback: the default method.
      final userMethods = await methods.listForUser(payerId);
      if (userMethods.isEmpty) {
        throw ApiError.badRequest(
            'Ajoutez d\'abord un moyen de paiement');
      }
      methodRow = userMethods.firstWhere(
        (m) => (m['par_defaut'] as int) == 1,
        orElse: () => userMethods.first,
      );
    }

    final methodType =
        PaymentMethodType.parse(methodRow['type'] as String);
    final payerSolde = users.soldeOf(payer);
    final walletSufficient =
        payerSolde - montantCentimes >= 0;

    final useWallet = methodType == PaymentMethodType.portefeuille;
    final finalStatus = !useWallet
        ? TransactionStatus.paye
        : (walletSufficient ? TransactionStatus.paye : TransactionStatus.echoue);

    late int transactionId;
    await _db.transaction((txn) async {
      // facture_numero derives from the next AUTOINCREMENT id, computed
      // inside the transaction (ids are never reused).
      final nextId = ((await txn.rawQuery(
                'SELECT COALESCE(MAX(id), 0) + 1 AS n FROM transaction_',
              ))
                  .first['n'] as int)
          .clamp(1, 1 << 62);
      final year = DateTime.now().year;
      final factureNumero =
          'FAC-$year-${nextId.toString().padLeft(6, '0')}';

      if (finalStatus == TransactionStatus.paye) {
        if (useWallet) {
          await txn.update('utilisateur',
              {'solde_centimes': payerSolde - montantCentimes},
              where: 'id = ?', whereArgs: [payerId]);
        }
        final benefSolde =
            users.soldeOf(beneficiaire);
        await txn.update('utilisateur',
            {'solde_centimes': benefSolde + montantCentimes},
            where: 'id = ?', whereArgs: [beneficiaire['id'] as int]);
      }
      transactionId = await txn.insert('transaction_', {
        'montant_centimes': montantCentimes,
        'devise': 'TND',
        'date': DateTime.now().toIso8601String(),
        'statut': finalStatus.apiValue,
        'type_service': typeService.apiValue,
        'id_reference': idReference?.trim().isEmpty ?? true
            ? null
            : idReference!.trim(),
        'facture_numero': factureNumero,
        'utilisateur_id': payerId,
        'beneficiaire_id': beneficiaire['id'] as int,
        'moyen_paiement_id': methodRow!['id'] as int,
      });
    });

    final row = await transactions.findById(transactionId);
    return transactions.toDto(row!);
  }

  Future<TransactionDto> getTransaction(
      int id, int requesterId, UserRole requesterRole) async {
    final row = await transactions.findById(id);
    if (row == null) throw ApiError.notFound('Transaction introuvable');
    final payerId = row['utilisateur_id'] as int?;
    final beneficiaireId = row['beneficiaire_id'] as int?;
    final canSee = payerId == requesterId ||
        beneficiaireId == requesterId ||
        requesterRole == UserRole.admin;
    if (!canSee) throw ApiError.forbidden('Accès refusé');
    return transactions.toDto(row);
  }

  /// paye → rembourse. Initiated by the payer (or an admin). The payer's
  /// wallet is credited back, the beneficiary is debited (rejected if their
  /// balance can't cover it).
  Future<TransactionDto> refund(
      int id, int requesterId, UserRole requesterRole) async {
    final row = await transactions.findById(id);
    if (row == null) throw ApiError.notFound('Transaction introuvable');
    final payerId = row['utilisateur_id'] as int?;
    if (payerId != requesterId && requesterRole != UserRole.admin) {
      throw ApiError.forbidden(
          'Seul le payeur peut demander un remboursement');
    }
    final statut = TransactionStatus.parse(row['statut'] as String);
    if (!TransactionRules.canTransition(statut, TransactionStatus.rembourse)) {
      throw ApiError.conflict(
          'Seule une transaction payée peut être remboursée');
    }

    final amount = row['montant_centimes'] as int;
    final beneficiaireId = row['beneficiaire_id'] as int?;
    if (beneficiaireId == null || payerId == null) {
      throw ApiError.conflict(
          'Transaction anonymisée : remboursement impossible');
    }
    final payer = (await users.findById(payerId))!;
    final beneficiaire = (await users.findById(beneficiaireId))!;
    final benefSolde = users.soldeOf(beneficiaire);
    if (benefSolde < amount) {
      throw ApiError.conflict(
          'Solde du bénéficiaire insuffisant pour le remboursement');
    }

    // All statements go through the transaction object: using the outer
    // database handle inside an open transaction deadlocks sqflite.
    await _db.transaction((txn) async {
      await txn.update('utilisateur',
          {'solde_centimes': benefSolde - amount},
          where: 'id = ?', whereArgs: [beneficiaireId]);
      await txn.update('utilisateur',
          {'solde_centimes': users.soldeOf(payer) + amount},
          where: 'id = ?', whereArgs: [payerId]);
      await txn.update('transaction_',
          {'statut': TransactionStatus.rembourse.apiValue},
          where: 'id = ?', whereArgs: [id]);
    });

    return getTransaction(id, requesterId, requesterRole);
  }

  /// Cancels a pending transaction (payer or admin only).
  Future<void> cancel(
      int id, int requesterId, UserRole requesterRole) async {
    final row = await transactions.findById(id);
    if (row == null) throw ApiError.notFound('Transaction introuvable');
    final payerId = row['utilisateur_id'] as int?;
    if (payerId != requesterId && requesterRole != UserRole.admin) {
      throw ApiError.forbidden('Accès refusé');
    }
    final statut = TransactionStatus.parse(row['statut'] as String);
    if (!TransactionRules.canCancel(statut)) {
      throw ApiError.conflict(
          'Seule une transaction en attente peut être annulée');
    }
    await transactions.delete(id);
  }

  Future<Map<String, Object?>> _ownMethod(
      int utilisateurId, int methodId) async {
    final row = await methods.findById(methodId);
    if (row == null || row['utilisateur_id'] != utilisateurId) {
      throw ApiError.notFound('Moyen de paiement introuvable');
    }
    return row;
  }
}
