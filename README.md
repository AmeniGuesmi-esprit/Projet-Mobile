# ProxiLife

Application mobile Flutter de services de proximité : un compte unique, un
portefeuille de paiement unifié, des paiements internes entre comptes.

Modules livrés ici :

- **Gestion Utilisateur** — compte, vérification par e-mail, connexion
  biométrique, RIB pour les professionnels.
- **Gestion Paiement** — moyens de paiement, transactions internes avec solde,
  historique, factures, remboursements.

## Démarrage rapide

Prérequis : Flutter SDK, Android Studio + émulateur Android, Git.

```bash
# 1. Dépendances
cd packages/proxilife_shared && dart pub get
cd ../../server && dart pub get
cd ../app && flutter pub get

# 2. Configurer le serveur (une fois)
cd ../server
cp .env.example .env          # mode console par défaut : pas d'envoi SMTP.
                              # Le code de vérification s'affiche dans le
                              # terminal du serveur. (E-mail réel : plus tard.)

# 3. Base de données de démo
dart run bin/seed.dart

# 4. Lancer le serveur (terminal 1)
dart run bin/server.dart      # http://127.0.0.1:8080

# 5. Lancer l'app sur l'émulateur (terminal 2)
cd ../app
flutter run -d emulator-5554
```

Comptes de démo (mot de passe : `Proxilife2026!`) :

| E-mail | Rôle | Usage |
|---|---|---|
| `client@proxilife.fr` | client | payer, gérer ses moyens |
| `conducteur@proxilife.fr` | conducteur | recevoir des paiements (RIB) |
| `admin@proxilife.fr` | admin | supervision, remboursements |

## Structure

- `app/` — application Flutter.
- `server/` — API REST Dart locale (`shelf` + `sqflite`).
- `packages/proxilife_shared/` — énumérations, validateurs et machine à états
  partagés entre l'app et le serveur.
- `AGENTS.md` — conventions et commandes de vérification.
- `.devin/skills/` — règles de design et d'UX utilisées pour construire l'UI.

## Vérification

```bash
cd packages/proxilife_shared && dart analyze && dart test
cd ../../server && dart analyze && dart test
cd ../app && flutter analyze && flutter test
```
