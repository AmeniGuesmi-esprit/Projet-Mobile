# AGENTS.md — ProxiLife

Shared conventions for ProxiLife (Flutter frontend + local Dart REST server).

## Layout

| Path | Description |
|---|---|
| `packages/proxilife_shared/` | Pure-Dart shared code : enums, validators, transaction state machine, DTOs (no codegen). |
| `server/` | Dart `shelf` REST API on `127.0.0.1:8080`, sqflite via `sqflite_common_ffi`, config from `server/.env`. |
| `app/` | Flutter app (package `com.proxilife.app`). All UI in French, code in English. |
| `.devin/skills/` | Devin skills: `proxilife-ui-design`, `flutter-ux-patterns`. |

## Languages

- All user-visible strings: **French** (fields, messages, error texts).
- All identifiers, file names, classes, variables: **English**.

## No codegen

None. All `fromJson` / `toJson` are hand-written in `proxilife_shared`, same for
HIVE / build_runner. They are **not** used in this project.

## Verification (run before any commit)

```bash
# Shared
cd packages/proxilife_shared && dart analyze && dart test

# Server
cd ../../server && dart analyze && dart test && dart run bin/server.dart

# App (on Android emulator)
cd ../app && flutter analyze && flutter test && flutter run -d emulator-5554
```

## Verification rules

- Always validate on the **server**; validation in the app is UX-only.
- `lib` and `bin` must both be lint-clean (`core:recommended` / `package:lints).
- `dart test` / `flutter test` must be green before merging.
- No secrets in code or in commits (check `git status`, `git diff --staged`).

## Data conventions

- Money: **whole cents** (`int`), never `double`.
- Default currency: `EUR`.
- Emails: lowercase, unique.
- Transaction status transitions are defined once in
  `packages/proxilife_shared/lib/src/transaction_rules.dart` — never rewrite
  a second state machine.

## Server security

- Passwords: PBKDF2-HMAC-SHA256 (210 000 iterations) implemented on
  `package:crypto`'s HMAC (`lib/src/auth/passwords.dart`; pointycastle was
  dropped to avoid API churn).
- Session tokens: 32 random bytes, only their SHA-256 hash is stored in a DB,
  expiration 30 days.
- Verification codes: 6 digits, hashed SHA-256, maximum 5 attempts, 10 min expiry.
- Payment cards: Luhn at input, keep **only** the last 4 digits.
- Server listens on `127.0.0.1` only.

## Branch / PR flow

```
main ──> initial-setup ──> feat/user ──> feat/payment
```

PRs to be opened at merge time:
1. `initial-setup` → `main`
2. `feat/payment` → `feat/user`  (unified user+payment)
3. `feat/user` → `main` (everything in one PR)

**Never commit without explicit approval from the user.**

## Environment setup (Windows)

`.env` lives in `server/` and is **never** committed. Keep a copy in
`server/.env.example` (no secrets).

```
EMAIL_MODE=console               # default. SMTP (Gmail) is NOT set up yet —
                                 # no e-mail is sent, codes print in the
                                 # server terminal. Set to "smtp" + fill the
                                 # values below when the user asks for it.
SMTP_HOST=smtp.gmail.com
SMTP_PORT=465
SMTP_USER=your-email@gmail.com
SMTP_PASS=your-app-password      # 16-char Google App Password
DB_PATH=./proxi_life.db          # relative to server/
SERVER_PORT=8080
```

## Forbidden practices

- No HTTP cleartext above `debug` mode in `network_security_config.xml`.
- No `print` in production code — use `dart:developer`.
- No `devkoan` / custom code-style forks : stick to package `lints`.
- No `isar`, `hive`, `firebase`, `bloc`, `getx`: this project is deliberately
  bare-metal (`ChangeNotifier` + `FutureBuilder`).

## Useful third-party packages (current allowed versions)

| Package | Version | Where |
|---|---|---|
| shelf | ^1.4.2 | server |
| shelf_router | ^1.1.4 | server |
| sqflite_common_ffi | ^2.4.3 | server |
| crypto | ^3.0.7 | server |
| mailer | ^7.2.0 | server |
| path | ^1.9.1 | server |
| http | ^1.6.0 | app |
| shared_preferences | ^2.5.6 | app |
| flutter_secure_storage | ^11.2.0 | app |
| local_auth | ^3.0.2 | app |
| image_picker | ^1.2.4 | app |
| flutter_local_notifications | ^22.3.1 | app |
| intl | ^0.20.3 | app |

(If a newer version is on pub.dev but younger than 7 days at install time, pin
the previous one.)
