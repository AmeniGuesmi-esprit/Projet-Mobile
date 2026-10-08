import 'dart:io';

import 'package:proxilife_server/src/auth/passwords.dart';
import 'package:proxilife_server/src/db/database.dart';
import 'package:proxilife_server/src/config/server_config.dart';

/// Seed data: a client, a professional driver with a valid RIB, and an admin.
/// All share the password `Proxilife2026!`.
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
      'mot_de_passe_hash': hasher.hashPassword('Proxilife2026!'),
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

  stdout.writeln('Seed termine.');
  stdout.writeln('  client      : #$clientId  client@proxilife.fr');
  stdout.writeln('  conducteur  : #$conducteurId  conducteur@proxilife.fr');
  stdout.writeln('  admin       : #$adminId  admin@proxilife.fr');
  stdout.writeln('Mot de passe commun : Proxilife2026!');

  await db.close();
}
