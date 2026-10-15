import 'dart:io';

import 'package:proxilife_server/src/auth/passwords.dart';
import 'package:proxilife_server/src/db/database.dart';
import 'package:proxilife_server/src/config/server_config.dart';

/// Seed data: demo accounts. Default demo accounts share `Proxilife2026!`;
/// three extra accounts (fawzi.saidi@esprit.tn / ameni.guesmi@esprit.tn /
/// ameniguesmi2002@gmail.com) have their own passwords.
Future<void> main() async {
  final config = await ServerConfig.load();
  final db = await AppDatabase.open(config.dbPath);

  final hasher = const PasswordHasher();
  final now = DateTime.now().toIso8601String();

  Future<int?> upsertUser({
    required String nom,
    required String prenom,
    required String email,
    required String telephone,
    required String role,
    String? rib,
    int soldeCentimes = 0,
    String password = 'Proxilife2026!',
  }) async {
    final existing = await db.db.query(
      'utilisateur',
      where: 'email = ?',
      whereArgs: [email],
    );
    if (existing.isNotEmpty) {
      return existing.first['id'] as int;
    }
    return db.db.insert('utilisateur', {
      'nom': nom,
      'prenom': prenom,
      'email': email,
      'telephone': telephone,
      'mot_de_passe_hash': hasher.hashPassword(password),
      'photo': null,
      'role': role,
      'statut_compte': 'actif',
      'rib': rib,
      'solde_centimes': soldeCentimes,
      'cree_le': now,
    });
  }

  final clientId = await upsertUser(
    nom: 'Guesmi',
    prenom: 'Ameni',
    email: 'client@proxilife.fr',
    telephone: '0612345678',
    role: 'client',
    soldeCentimes: 5000,
  );
  final conducteurId = await upsertUser(
    nom: 'Saidi',
    prenom: 'Fawzi',
    email: 'conducteur@proxilife.fr',
    telephone: '0698765432',
    role: 'conducteur',
    rib: '30004000011234567890173',
  );
  final adminId = await upsertUser(
    nom: 'Admin',
    prenom: 'Proxi',
    email: 'admin@proxilife.fr',
    telephone: '0600000000',
    role: 'admin',
  );
  final fawziId = await upsertUser(
    nom: 'Saidi',
    prenom: 'Fawzi',
    email: 'fawzi.saidi@esprit.tn',
    telephone: '98123456',
    role: 'client',
    soldeCentimes: 5000,
    password: 'FawziSaidi221',
  );
  final ameniId = await upsertUser(
    nom: 'Guesmi',
    prenom: 'Ameni',
    email: 'ameni.guesmi@esprit.tn',
    telephone: '22123456',
    role: 'conducteur',
    rib: '30004000011234567890173',
    password: 'AmeniGuesmi112',
  );
  final commercantId = await upsertUser(
    nom: 'Guesmi',
    prenom: 'Ameni',
    email: 'ameniguesmi2002@gmail.com',
    telephone: '23456789',
    role: 'commercant',
    rib: '10107001202025004281795',
    password: 'Ameni@123',
  );

  // A couple of payment methods for the client, for demos.
  Future<int> addMethod(
    int utilisateurId, {
    required String type,
    String? last4,
    String? titulaire,
    String? expiration,
    bool parDefaut = false,
  }) {
    return db.db.insert('moyen_paiement', {
      'type': type,
      'quatre_derniers_chiffres': last4,
      'nom_titulaire': titulaire,
      'date_expiration': expiration,
      'par_defaut': parDefaut ? 1 : 0,
      'utilisateur_id': utilisateurId,
      'cree_le': now,
    });
  }

  final methodsCount = (await db.db.rawQuery(
    'SELECT COUNT(*) as c FROM moyen_paiement WHERE utilisateur_id = ?',
    [clientId],
  ))
      .first['c'] as int;
  if (methodsCount == 0 && clientId != null) {
    await addMethod(
      clientId,
      type: 'carte_bancaire',
      last4: '6467',
      titulaire: 'AMENI GUESMI',
      expiration: '10/29',
      parDefaut: true,
    );
    await addMethod(clientId, type: 'portefeuille', parDefaut: false);
    await addMethod(clientId, type: 'especes', parDefaut: false);
  }

  // Test data for the commerçant: own payment methods, payments received
  // from the demo client (every status) and one payment sent to a driver.
  // Balances are adjusted the way PaymentService would have.
  final commercantTxCount = (await db.db.rawQuery(
    'SELECT COUNT(*) AS c FROM transaction_ '
    'WHERE utilisateur_id = ? OR beneficiaire_id = ?',
    [commercantId, commercantId],
  ))
      .first['c'] as int;
  if (commercantId != null &&
      clientId != null &&
      conducteurId != null &&
      commercantTxCount == 0) {
    final commercantCard = await addMethod(
      commercantId,
      type: 'carte_bancaire',
      last4: '4242',
      titulaire: 'AMENI GUESMI',
      expiration: '08/28',
      parDefaut: true,
    );
    await addMethod(commercantId, type: 'portefeuille');

    Future<int> methodOf(int userId, String type) async =>
        (await db.db.query(
          'moyen_paiement',
          where: 'utilisateur_id = ? AND type = ?',
          whereArgs: [userId, type],
          limit: 1,
        ))
            .first['id'] as int;
    final clientCard = await methodOf(clientId, 'carte_bancaire');
    final clientWallet = await methodOf(clientId, 'portefeuille');

    final payments = <(int, int, int, int, String, String, String?, int)>[
      // (payer, beneficiary, method, cents, status, service, ref, daysAgo)
      (clientId, commercantId, clientCard, 4500, 'paye', 'FoodSave',
          'Panier anti-gaspi #1042', 28),
      (clientId, commercantId, clientCard, 12000, 'paye', 'ServiceNow',
          'Livraison épicerie', 21),
      (clientId, commercantId, clientCard, 3250, 'rembourse', 'FoodSave',
          'Panier #1057', 15),
      (commercantId, conducteurId, commercantCard, 1800, 'paye', 'EcoRoute',
          'Course centre-ville', 12),
      (clientId, commercantId, clientCard, 8900, 'paye', 'FoodSave',
          'Commande #1063', 9),
      (clientId, commercantId, clientWallet, 20000, 'echoue', 'ServiceNow',
          null, 6),
      (clientId, commercantId, clientCard, 15600, 'paye', 'ServiceNow',
          'Installation vitrine', 2),
      (clientId, commercantId, clientCard, 5000, 'en_attente', 'FoodSave',
          'Commande #1071', 0),
    ];

    final soldeDelta = <int, int>{};
    await db.db.transaction((txn) async {
      for (final (payer, benef, method, cents, statut, service, ref, days)
          in payments) {
        final date = DateTime.now().subtract(Duration(days: days, hours: 3));
        final nextId = (await txn.rawQuery(
          'SELECT COALESCE(MAX(id), 0) + 1 AS n FROM transaction_',
        ))
            .first['n'] as int;
        await txn.insert('transaction_', {
          'montant_centimes': cents,
          'devise': 'TND',
          'date': date.toIso8601String(),
          'statut': statut,
          'type_service': service,
          'id_reference': ref,
          'facture_numero':
              'FAC-${date.year}-${nextId.toString().padLeft(6, '0')}',
          'utilisateur_id': payer,
          'beneficiaire_id': benef,
          'moyen_paiement_id': method,
        });
        if (statut == 'paye') {
          soldeDelta[benef] = (soldeDelta[benef] ?? 0) + cents;
        } else if (statut == 'rembourse') {
          // Paid then refunded: the payer's wallet got the money back.
          soldeDelta[payer] = (soldeDelta[payer] ?? 0) + cents;
        }
      }
      for (final MapEntry(key: userId, value: delta) in soldeDelta.entries) {
        await txn.rawUpdate(
          'UPDATE utilisateur SET solde_centimes = solde_centimes + ? '
          'WHERE id = ?',
          [delta, userId],
        );
      }
    });
  }

  // FoodSave demo data: the commerçant's store, two client positions (one
  // within the 5 km notification radius, one outside) and 4 baskets.
  // Idempotent: store/positions inserted once, baskets only when the store
  // has none. All FoodSave timestamps are UTC ISO-8601.
  if (commercantId != null) {
    final nowUtc = DateTime.now().toUtc();
    String utc(Duration fromNow) => nowUtc.add(fromNow).toIso8601String();
    final nowIso = nowUtc.toIso8601String();

    await db.db.rawInsert(
      'INSERT OR IGNORE INTO commerce (commercant_id, nom, adresse, latitude, '
      'longitude, categorie, cree_le, mis_a_jour_le) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        commercantId,
        'Boulangerie Ameni',
        'Avenue Habib Bourguiba, Tunis',
        36.8008,
        10.1800,
        'boulangerie',
        nowIso,
        nowIso,
      ],
    );

    for (final (userId, lat, lng) in [
      (clientId, 36.8065, 10.1815), // ≈ 0.6 km from the store
      (fawziId, 36.8782, 10.3247), // ≈ 15 km, outside the radius
    ]) {
      if (userId == null) continue;
      await db.db.rawInsert(
        'INSERT OR IGNORE INTO localisation_client '
        '(utilisateur_id, latitude, longitude, mis_a_jour_le) '
        'VALUES (?, ?, ?, ?)',
        [userId, lat, lng, nowIso],
      );
    }

    final basketCount = (await db.db.rawQuery(
      'SELECT COUNT(*) AS c FROM panier WHERE commercant_id = ?',
      [commercantId],
    ))
        .first['c'] as int;
    if (basketCount == 0) {
      final baskets = <(String, String, String, int, int, int, int, String,
          Duration, Duration, Duration)>[
        // (titre, contenu, categorie, prix, prix initial, quantite,
        //  quantite initiale, statut, début, fin, expiration)
        (
          'Panier du soir',
          'Baguettes, pain complet et 2 viennoiseries du jour',
          'boulangerie',
          500,
          1500,
          5,
          5,
          'disponible',
          const Duration(hours: 2),
          const Duration(hours: 4),
          const Duration(hours: 6),
        ),
        (
          'Douceurs du matin',
          'Croissants, pains au chocolat et une part de tarte',
          'patisserie',
          600,
          1800,
          3,
          3,
          'disponible',
          const Duration(hours: 18),
          const Duration(hours: 20),
          const Duration(hours: 22),
        ),
        (
          'Panier mixte surprise',
          'Pain, fromage frais, yaourts et fruits de saison',
          'mixte',
          800,
          2500,
          2,
          2,
          'disponible',
          const Duration(hours: 1),
          const Duration(hours: 3),
          const Duration(hours: 5),
        ),
        (
          'Pain de la veille',
          'Lot de 4 baguettes de la veille, idéales pour le pain perdu',
          'boulangerie',
          200,
          700,
          0,
          4,
          'epuise',
          const Duration(hours: 1),
          const Duration(hours: 5),
          const Duration(hours: 8),
        ),
      ];
      for (final (titre, contenu, categorie, prix, prixInitial, quantite,
          quantiteInitiale, statut, debut, fin, expiration) in baskets) {
        await db.db.insert('panier', {
          'titre': titre,
          'contenu': contenu,
          'categorie': categorie,
          'image': null,
          'prix_centimes': prix,
          'prix_initial_centimes': prixInitial,
          'quantite': quantite,
          'quantite_initiale': quantiteInitiale,
          'creneau_retrait_debut': utc(debut),
          'creneau_retrait_fin': utc(fin),
          'date_expiration': utc(expiration),
          'statut': statut,
          'commercant_id': commercantId,
          'cree_le': nowIso,
          'mis_a_jour_le': nowIso,
        });
      }
    }
  }

  stdout.writeln('Seed termine.');
  stdout.writeln('  client      : #$clientId  client@proxilife.fr');
  stdout.writeln('  conducteur  : #$conducteurId  conducteur@proxilife.fr');
  stdout.writeln('  admin       : #$adminId  admin@proxilife.fr');
  stdout.writeln('  fawzi       : #$fawziId  fawzi.saidi@esprit.tn');
  stdout.writeln('  ameni       : #$ameniId  ameni.guesmi@esprit.tn');
  stdout.writeln('  commercant  : #$commercantId  ameniguesmi2002@gmail.com');
  stdout.writeln('Mot de passe commun (demo) : Proxilife2026!');
  stdout.writeln('  fawzi.saidi@esprit.tn    : FawziSaidi221');
  stdout.writeln('  ameni.guesmi@esprit.tn    : AmeniGuesmi112');
  stdout.writeln('  ameniguesmi2002@gmail.com : Ameni@123');

  await db.close();
}
