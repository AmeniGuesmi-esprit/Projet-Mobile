---
name: flutter-ux-patterns
description: ProxiLife UX patterns — forms, async states with FutureBuilder, destructive confirmations, biometric login, accessibility and feedback for an amazing mobile UX.
allowed-tools:
  - read
  - grep
  - glob
  - edit
---

# ProxiLife Flutter UX Patterns

Use this skill when you build flows and screens in `app/`. Always deliver
**amazing UX**: forgiving forms, obvious feedback, zero dead ends.

## Forms

- Use `Form` + `GlobalKey<FormState>`; validate with `validate()` on submit.
- Live validation: `autovalidateMode: AutovalidateMode.onUserInteraction`.
- Show field-level errors under the field, concise and French; never red borders alone.
- Keyboard types: `TextInputType.emailAddress` for e-mails, `number` for codes/RIB (visible digits), `multiline` only for long text.
- Wrap auth forms in `AutofillGroup` with `TextInputAction` chain (`next` between fields, `done` on last) and content-type `autofillHints` (`AutofillHints.email`, `AutofillHints.password`).
- Role-based visibility (e.g. the RIB field only for professional roles) uses `AnimatedSize` + `AnimatedSwitcher`, 200 ms.
- Buttons: full width, 52 dp height, disabled state while submitting, loading indicator inside the button during async submit (not a separate screen loader).
- Never clear a form on error; keep user input.

## Async states with FutureBuilder (course-aligned)

Every screen loading remote data uses:

```dart
FutureBuilder<T>(
  future: future,
  builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.hasError) {
      return ErrorRetry(message: 'Message convivial en français', onRetry: refresh);
    }
    final data = snapshot.data!;
    if (data.isEmpty) {
      return const EmptyState(...);
    }
    return ContentList(data); // the loaded content
  },
)
```

- Re-trigger loads with `setState(() => future = _load())` — not with pull hacks.
- `RefreshIndicator` for lists.
- On a SnackBar error from an action (voucher/payment), show it as **floating** snackbar (theme defaults) with a corrective verb (« Réessayer »).

## Navigation

- Simple `Navigator` pushes per action, no routing package until needed.
- After a destructive delete (account, payment method), pop until root and show confirmation snackbar.
- Bottom sheet for "quick action" choices; full page for forms > 3 fields.

## Destructive confirmations

- Two-step: AlertDialog (« Supprimer définitivement… ») with **danger button** (`error` colour, FilledButton style override), then a final typed confirmation "SUPPRIMER" only for account deletion.
- Payment method / transaction cancel: single AlertDialog is enough.

## Biometric login (local_auth)

- Offer empreinte / Face ID *after* a successful password login (« Activer la connexion biométrique ? ») — never before.
- Biometric unlock reads the session token from `flutter_secure_storage`; password always available as fallback (button « Utiliser mon mot de passe »).
- On `local_auth` errors (no hardware, not enrolled) fall back silently to password login with an info snackbar.
- Requires `FlutterFragmentActivity` in MainActivity (already configured).

## Money & amounts

- Store/transport whole cents (`int`); never `double`.
- Format with `intl` (`NumberFormat.currency(locale: 'fr_FR', symbol: '€')`).
- Amount input: `TextFormField` with decimal filter, parsed carefully (`,` or `.` separators), reject zero/negative.

## Verification codes

- Six separate boxes (6 `TextField` width 44 or a package-free design) with auto-advance; paste fills all boxes.
- Resend button with 60 s countdown (`Timer`), disabled while counting.
- 5 attempts max (server-enforced); after the last attempt, show helpful message + « Renvoyer le code ».

## Notifications (flutter_local_notifications)

- Ask `POST_NOTIFICATIONS` permission on Android 13+ once, from Settings screen (« Notifications » toggle), not at first open.
- Local notifications for: compte vérifié, paiement effectué, remboursement reçu.

## Accessibility

- Touch targets ≥ 48 dp. Tappable icons use `IconButton` with `tooltip` in French.
- Respect text scaling (avoid fixed-height text rows below 40 logical px).
- Meaningful `Semantics` labels on avatar/list actions.

## Screen sizes

- Design for ~360–430 dp widths; forms in scrollable `ListView` (`keyboardDismissBehavior: onDrag`), `resizeToAvoidBottomInset` default.
- No landscape-specific layout required; avoid overflowing rows (use `Expanded`/`Wrap`).

## Offline/server down

- If the server is unreachable, show a friendly banner « Serveur local indisponible — vérifiez qu'il est lancé » with « Réessayer »; never a raw exception text.
- API base URL via `--dart-define=API_BASE_URL` default `http://10.0.2.2:8080`.
