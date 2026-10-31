import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../api_error.dart';
import '../repositories/payment_method_repository.dart';
import '../repositories/transaction_repository.dart';
import '../repositories/user_repository.dart';

/// Business rules for payment methods and internal transactions.
///
/// Money semantics per payment method type (single source of truth):
/// - carte_bancaire : simulated bank charge, immediately `paye`; the
///   beneficiary's internal wallet is credited.
/// - portefeuille : debits the payer's internal wallet, credited to the
///   beneficiary; insufficient balance yields an `echoue` record with no
///   money moved. The balance is re-checked **inside** the SQL transaction.
/// - especes : cash physically changes hands, so the transaction is created
///   `en_attente` with **no internal movement**. The beneficiary confirms
///   receipt (`en_attente -> paye`); the payer may cancel while pending.
///
/// Refunds mirror the original method:
/// - portefeuille : symmetric reversal (beneficiary debited, payer credited).
/// - carte_bancaire : the bank reverses the charge, so only the beneficiary
///   is debited internally; the payer is reimbursed "on their card".
/// - especes : status change only — cash is handed back physically.
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

  int _tmpFactureCounter = 0;

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
    return rows.map((r) => transactions.toDto(r, forUserId: utilisateurId)).toList();
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
    final beneficiaireId = beneficiaire['id'] as int;
    final useWallet = methodType == PaymentMethodType.portefeuille;
    final isCash = methodType == PaymentMethodType.especes;

    late int transactionId;
    await _db.transaction((txn) async {
      // Cash waits for the beneficiary's confirmation; the wallet balance is
      // re-checked inside the transaction so concurrent payments can't
      // overdraw it.
      TransactionStatus finalStatus;
      if (isCash) {
        finalStatus = TransactionStatus.enAttente;
      } else if (useWallet) {
        final solde = await users.soldeOfId(txn, payerId);
        finalStatus = solde >= montantCentimes
            ? TransactionStatus.paye
            : TransactionStatus.echoue;
      } else {
        finalStatus = TransactionStatus.paye;
      }

      if (finalStatus == TransactionStatus.paye) {
        if (useWallet) {
          await users.addSolde(txn, payerId, -montantCentimes);
        }
        await users.addSolde(txn, beneficiaireId, montantCentimes);
      }

      // Temporary unique invoice number; replaced with the canonical
      // FAC-<year>-<real id> right below, inside the same transaction.
      final tmpFacture =
          'TMP-${DateTime.now().year}-${++_tmpFactureCounter}-'
          '${DateTime.now().microsecondsSinceEpoch}';
      transactionId = await txn.insert('transaction_', {
        'montant_centimes': montantCentimes,
        'devise': 'TND',
        'date': DateTime.now().toIso8601String(),
        'statut': finalStatus.apiValue,
        'type_service': typeService.apiValue,
        'id_reference': idReference?.trim().isEmpty ?? true
            ? null
            : idReference!.trim(),
        'facture_numero': tmpFacture,
        'utilisateur_id': payerId,
        'beneficiaire_id': beneficiaireId,
        'moyen_paiement_id': methodRow!['id'] as int,
      });
      final factureNumero = 'FAC-${DateTime.now().year}-'
          '${transactionId.toString().padLeft(6, '0')}';
      await txn.update(
        'transaction_',
        {'facture_numero': factureNumero},
        where: 'id = ?',
        whereArgs: [transactionId],
      );
    });

    final row = await transactions.findById(transactionId);
    return transactions.toDto(row!, forUserId: payerId);
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
    return transactions.toDto(row, forUserId: requesterId);
  }

  /// enAttente → paye. Only the beneficiary (or an admin) confirms, and only
  /// cash transactions ever wait: nothing internal moves at confirmation,
  /// the cash was settled physically.
  Future<TransactionDto> confirm(
      int id, int requesterId, UserRole requesterRole) async {
    final row = await transactions.findById(id);
    if (row == null) throw ApiError.notFound('Transaction introuvable');
    final beneficiaireId = row['beneficiaire_id'] as int?;
    if (beneficiaireId != requesterId && requesterRole != UserRole.admin) {
      throw ApiError.forbidden(
          'Seul le bénéficiaire peut confirmer la réception');
    }
    final statut = TransactionStatus.parse(row['statut'] as String);
    if (!TransactionRules.canTransition(statut, TransactionStatus.paye)) {
      throw ApiError.conflict(
          'Seule une transaction en attente peut être confirmée');
    }
    await transactions.updateStatus(id, TransactionStatus.paye);
    return getTransaction(id, requesterId, requesterRole);
  }

  /// paye → rembourse. Initiated by the payer (or an admin). Money moves
  /// according to the original method (see class doc).
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
    final methodType = row['mp_type'] == null
        ? null
        : PaymentMethodType.parse(row['mp_type'] as String);

    // All statements go through the transaction object: using the outer
    // database handle inside an open transaction deadlocks sqflite.
    await _db.transaction((txn) async {
      if (methodType == PaymentMethodType.portefeuille ||
          methodType == PaymentMethodType.carteBancaire) {
        final benefSolde = await users.soldeOfId(txn, beneficiaireId);
        if (benefSolde < amount) {
          throw ApiError.conflict(
              'Solde du bénéficiaire insuffisant pour le remboursement');
        }
        await users.addSolde(txn, beneficiaireId, -amount);
        if (methodType == PaymentMethodType.portefeuille) {
          // Wallet refund: exact reversal. Card refund: the payer is
          // reimbursed by the (simulated) bank on their card, so no
          // internal credit happens here.
          await users.addSolde(txn, payerId, amount);
        }
      }
      // Cash: nothing internal ever moved — status change only.
      await txn.update('transaction_',
          {'statut': TransactionStatus.rembourse.apiValue},
          where: 'id = ?', whereArgs: [id]);
    });

    return getTransaction(id, requesterId, requesterRole);
  }

  /// Cancels (deletes) a pending transaction (payer or admin only).
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
