import 'dart:io';

import 'package:proxilife_server/src/auth/passwords.dart';
import 'package:proxilife_server/src/db/database.dart';
import 'package:proxilife_server/src/config/server_config.dart';

/// Seed data: demo accounts. Default demo accounts share `Proxilife2026!`;
/// the team accounts have their own passwords.
///
/// Re-running the seed refreshes password, balance, role and RIB of known
/// accounts, so the demo state stays deterministic.
///
/// NOTE: fawzi.saidi@esprit.tn is intentionally NOT seeded — that account is
/// created live through the SMTP registration flow (e-mail verification
/// demo). Registering it requires a password with a digit: `FawziSaidi2026`.
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
      final id = existing.first['id'] as int;
      await db.db.update(
        'utilisateur',
        {
          'nom': nom,
          'prenom': prenom,
          'telephone': telephone,
          'mot_de_passe_hash': hasher.hashPassword(password),
          'role': role,
          'rib': rib,
          'solde_centimes': soldeCentimes,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
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
  // fawzi.saidi@esprit.tn : volontairement non seedé (inscription SMTP live).
  final ameniId = await upsertUser(
    nom: 'Guesmi',
    prenom: 'Ameni',
    email: 'ameni.guesmi@esprit.tn',
    telephone: '22123456',
    role: 'conducteur',
    rib: '30004000011234567890173',
    soldeCentimes: 2000,
    password: 'AmeniGuesmi',
  );
  final marahId = await upsertUser(
    nom: 'Mabrouk',
    prenom: 'Marah',
    email: 'marah.mabrouk@esprit.tn',
    telephone: '55111222',
    role: 'commercant',
    rib: '30004000011234567890173',
    soldeCentimes: 2500,
    password: 'MarahMabrouk',
  );
  final farahId = await upsertUser(
    nom: 'Chbeb',
    prenom: 'Farah',
    email: 'farah.chbeb@esprit.tn',
    telephone: '23222333',
    role: 'medecin',
    rib: '30004000011234567890173',
    soldeCentimes: 2500,
    password: 'FarahChbeb',
  );
  final yasmineId = await upsertUser(
    nom: 'Chakroun',
    prenom: 'Yasmine',
    email: 'yasmine.chakroun@esprit.tn',
    telephone: '29222333',
    role: 'coach',
    rib: '30004000011234567890173',
    soldeCentimes: 1500,
    password: 'YasmineChakroun',
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
  stdout.writeln('  client      : #$clientId  client@proxilife.fr (50,00 DT)');
  stdout.writeln('  conducteur  : #$conducteurId  conducteur@proxilife.fr');
  stdout.writeln('  admin       : #$adminId  admin@proxilife.fr');
  stdout.writeln('  ameni       : #$ameniId  ameni.guesmi@esprit.tn (20,00 DT)');
  stdout.writeln('  marah       : #$marahId  marah.mabrouk@esprit.tn (25,00 DT)');
  stdout.writeln('  farah       : #$farahId  farah.chbeb@esprit.tn (25,00 DT)');
  stdout
      .writeln('  yasmine     : #$yasmineId  yasmine.chakroun@esprit.tn (15,00 DT)');
  stdout.writeln('Mot de passe commun (demo) : Proxilife2026!');
  stdout.writeln('  ameni.guesmi@esprit.tn    : AmeniGuesmi');
  stdout.writeln('  marah.mabrouk@esprit.tn   : MarahMabrouk');
  stdout.writeln('  farah.chbeb@esprit.tn     : FarahChbeb');
  stdout.writeln('  yasmine.chakroun@esprit.tn: YasmineChakroun');
  stdout.writeln(
      'fawzi.saidi@esprit.tn : NON seedé — inscription via SMTP (FawziSaidi2026)');

  await db.close();
}
