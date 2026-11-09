# ProxiLife

Application mobile Flutter de services de proximité : un compte unique, un
portefeuille de paiement unifié et plusieurs services réunis dans une même
application.

## Modules

| Module | Ce qu'il fait |
|---|---|
| **Gestion Utilisateur** | Inscription avec vérification par e-mail, connexion (biométrique en option), profil, RIB pour les professionnels. |
| **Gestion Paiement** | Portefeuille et solde, moyens de paiement (carte : seuls les 4 derniers chiffres sont gardés), paiements internes entre comptes, historique, reçus, remboursements. |
| **FoodSave** (anti-gaspillage) | Les commerçants publient leurs invendus en paniers ; les clients les trouvent près d'eux, réservent, paient et retirent avec un QR code (reçu aussi par e-mail). Itinéraire Google Maps, filtres, notifications. |
| **EcoRoute** (covoiturage) | Les conducteurs publient des trajets et acceptent les demandes ; les passagers recherchent et réservent. Embarquement par QR code ou Bluetooth. |
| **TeleDoc Express** (téléconsultation) | File d'attente virtuelle, appel audio/vidéo, ordonnance, pharmacies de garde, historique des consultations. Voir [docs/teledoc](docs/teledoc/README.md). |
| **CoachProche** (sport) | Les coachs publient des séances ; les clients réservent, valident leur présence par QR code et suivent leur activité. Rappels avant séance. |
| **ServiceNow** (services à domicile) | Demandes de plomberie, électricité, ménage… ; mise en relation avec les prestataires proches selon leurs spécialités, suivi des interventions et messagerie. |

### Parcours dans l'application

- Au premier lancement : une **page d'accueil** présente les services, avec
  « Commencer » (connexion) et « Créer un compte ».
- Une fois connecté : barre du bas **Accueil · Paiements · FoodSave ·
  EcoRoute · TeleDoc · Coach · ServiceNow · Profil**. L'onglet Accueil
  affiche le solde et des raccourcis vers chaque service.
- Chaque module s'adapte au rôle : par exemple le conducteur voit « Mes
  trajets / Demandes » dans EcoRoute, les autres rôles « Rechercher /
  Réservations » ; le médecin voit sa file de patients dans TeleDoc, les
  autres rôles consultent en tant que patient.
- La déconnexion ramène à l'écran de connexion.

## Démarrage rapide

Prérequis : Flutter SDK, Android Studio (SDK Android + émulateur), Git.

```bash
# 1. Dépendances
cd packages/proxilife_shared && dart pub get
cd ../../server && dart pub get
cd ../app && flutter pub get

# 2. Configurer le serveur (une fois)
cd ../server
cp .env.example .env          # EMAIL_MODE=console par défaut : aucun e-mail
                              # n'est envoyé, les codes de vérification
                              # s'affichent dans le terminal du serveur.
                              # EMAIL_MODE=smtp + identifiants Gmail pour un
                              # envoi réel.

# 3. Base de données de démo (comptes, médecins, pharmacies, séances…)
dart run bin/seed.dart

# 4. Lancer le serveur (terminal 1)
dart run bin/server.dart      # port 8080 ; l'émulateur y accède par
                              # http://10.0.2.2:8080

# 5. Lancer l'app sur l'émulateur (terminal 2)
cd ../app
flutter run -d emulator-5554
```

`dart run bin/seed.dart` peut être relancé : il remet les mots de passe, les
soldes et les rôles des comptes de démo à leur valeur initiale.

### Si le port 8080 est déjà pris

Lancer le serveur sur un autre port et l'indiquer à l'app :

```powershell
# PowerShell, dans server/
$env:SERVER_PORT = "8081"; dart run bin/server.dart
```

```bash
# dans app/
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8081
```

### Sur un téléphone Android réel (USB)

Activer le débogage USB sur le téléphone, le brancher, puis rediriger le
port du téléphone vers le serveur du PC :

```bash
adb reverse tcp:8080 tcp:8080          # ou tcp:8080 tcp:8081 si le serveur est sur 8081
cd app
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8080
```

La redirection `adb reverse` est perdue si le câble se débranche : la
relancer après chaque reconnexion.

## Comptes de démo

Créés par `dart run bin/seed.dart`.

| E-mail | Mot de passe | Rôle |
|---|---|---|
| `client@proxilife.fr` | `Proxilife2026!` | client (solde 50,00 DT) |
| `conducteur@proxilife.fr` | `Proxilife2026!` | conducteur |
| `admin@proxilife.fr` | `Proxilife2026!` | admin |
| `ameni.guesmi@esprit.tn` | `AmeniGuesmi` | conducteur |
| `marah.mabrouk@esprit.tn` | `MarahMabrouk` | commerçant |
| `ameniguesmi2002@gmail.com` | `Ameni@123` | commerçant (FoodSave) |
| `farah.chbeb@esprit.tn` | `FarahChbeb` | médecin |
| `dr.bensalah@proxilife.fr`, `dr.trabelsi@proxilife.fr`, `dr.jaziri@proxilife.fr` | `Proxilife2026!` | médecin (TeleDoc) |
| `patient2@proxilife.fr`, `patient3@proxilife.fr` | `Proxilife2026!` | client (patients TeleDoc) |
| `yasmine.chakroun@esprit.tn` | `YasmineChakroun` | coach (CoachProche) |
| `farrahamami@gmail.com` | `FarahAmami` | prestataire (ServiceNow) |
| `prestataire@proxilife.fr` | `Proxilife2026!` | prestataire (ServiceNow) |

`fawzi.saidi@esprit.tn` n'est volontairement pas créé par le seed : il sert à
montrer l'inscription avec vérification par e-mail (mot de passe utilisé en
démo : `FawziSaidi2026`).

## Structure

- `app/` — application Flutter (interface en français, code en anglais).
- `server/` — API REST Dart locale (`shelf` + SQLite via `sqflite_common_ffi`),
  configurée par `server/.env`.
- `packages/proxilife_shared/` — énumérations, validateurs, DTO et machine à
  états des transactions, partagés entre l'app et le serveur.
- `docs/` — documentation détaillée par module (TeleDoc).
- `.devin/skills/` — règles de design et d'UX utilisées pour l'interface.

## Vérification

À lancer avant chaque commit :

```bash
cd packages/proxilife_shared && dart analyze && dart test
cd ../../server && dart analyze && dart test
cd ../app && flutter analyze && flutter test
```

Sous Windows, `dart test` côté serveur échoue tant que le serveur tourne (la
bibliothèque `sqlite3.dll` est verrouillée) : l'arrêter d'abord.
