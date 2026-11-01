---
name: proxilife-ui-design
description: ProxiLife visual identity — palette, typography, spacing, component recipes, motion, French copy tone and review checklist for every screen.
allowed-tools:
  - read
  - grep
  - glob
  - edit
---

# ProxiLife UI Design

Use this skill whenever you create or modify any screen, widget or theme in
`app/`. Make interfaces beautiful, consistent and accessible. UI text is
**French**; code identifiers are **English**.

## Colour tokens (single source of truth: `app/lib/core/theme/app_colors.dart`)

| Token | Hex | Usage |
|---|---|---|
| primary | #1B7F5C | Main actions, links, selected states, brand |
| primaryDeep | #0F4D38 | Balance card gradient end, pressed states |
| accent | #FF8A3D | One key action per screen only (e.g. "Payer"). Never the primary CTA by default. |
| background | #F5F8F6 | App scaffold |
| text | #1F2933 | Headings, body |
| textSecondary | #6B7A75 | Captions ≥ 14 pt, icons |
| textSecondaryStrong | #4F5E58 | Small secondary text (< 14 pt) for contrast |
| surface | #FFFFFF | Cards, sheets, inputs, NavigationBar |
| outline / outlineSoft | #DDE5E0 / #E9EFEC | Borders, dividers |
| success | #2E9E5B | Paid / verified states |
| info | #2F80ED | Pending / informational states |
| warning | #F2B84B | Expiring codes, cautions — text must be `text` on it |
| error | #D64545 | Errors, failed payments, destructive actions |

Module colours: Compte & Paiement `#1B7F5C`, EcoRoute `#2F80ED`,
FoodSave `#E07B1F`, TeleDoc Express `#E0525B`, CoachProche `#8E5BD9`.

### Contrast rules (never break these)

- White text on `primary`, `primaryDeep`, `moduleEcoRoute`, `moduleCoachProche`, `error`, `success`, `info`: OK.
- On `accent` and `warning`: **always dark text `#1F2933`**, never white.
- `moduleTeleDoc` #E0525B is visually close to `error` #D64545 — never use the raw module colour alone where it could read as an error. Pair it with the "TeleDoc" label or icon.
- `moduleFoodSave` is close to `accent` — for module chips use the tinted background recipe below, so modules never look like actions.
- Small text (< 14 pt): use `textSecondaryStrong`, not `textSecondary`.

### Tint recipe (chips, badges, icons)

`color.withValues(alpha: 0.10)` background + `color` icon/text, optional
`color.withValues(alpha: 0.35)` 1 px border. Never use the raw module colour
as a large solid background.

## Typography (Inter, bundled at `app/assets/fonts`)

| Style | Size | Weight | Usage |
|---|---|---|---|
| displaySmall | 32 | 800 | Hero, balance amount |
| headlineMedium | 24 | 700 | Screen title |
| titleLarge | 20 | 700 | Sections |
| titleMedium | 16 | 600 | Cards, list tiles, chips |
| bodyLarge | 16 | 400 | Reading text |
| bodyMedium | 14 | 400 | Secondary text (Strong colour) |
| bodySmall | 12 | 400 | Captions (Strong colour) |
| labelLarge | 15 | 600 | Buttons, labels |

## Spacing & shape (8-pt grid: `app/lib/core/theme/app_spacing.dart`)

- Space tokens: 4 / 8 / 12 / 16 / 20 / 24 / 32. Use multiples of 8 for layout rhythm.
- Radii: fields & buttons 16 (`AppRadius.md`), cards 20 (`AppRadius.lg`), sheets 28, chips pill.
- AppBar: transparent, left-aligned title, no elevation.
- Cards: flat (no elevation), white, 1 px `outlineSoft` border, 20 radius.
- Buttons: FilledButton (primary), OutlinedButton (secondary), TextButton (tertiary); minimum height 52; full width in forms.
- Inputs: filled white, 16 radius, border `outline`, focused border `primary` 1.6 px, error `#D64545`. Error text under the field, never only a red border.

## Component checklist (build these, don't improvise)

- PrimaryButton / OutlinedSecondaryButton — theme defaults, don't restyle locally.
- StatusChip — `en_attente` (info tint), `paye` (success tint), `echoue` (error tint), `rembourse` (warning tint with dark text) — label always in French.
- ServiceBadge — tinted module colour + label + icon (no raw colour areas).
- MoneyText — display amounts from cents with `intl` NumberFormat.currency(locale: 'fr_FR', symbol: '€'), bold, no decimals overflows.
- BalanceCard — gradient `primary → primaryDeep`, white text, 20 radius, 20 padding.
- EmptyState — tinted circle icon (72), title, optional message, centred.
- PaymentCardVisual — visual bank card mockup: brand green surface, last-4 in spaced mono, titular name, expiry.
- SectionHeader + list with dividers `outlineSoft`.

## Motion

- 200–300 ms curves easeOutCubic for sheets, tabs, FAB transitions.
- Loading placeholders (skeletons via AnimatedOpacity), never bare spinners full-screen when the layout is known — except for `FutureBuilder` initial loads.
- Press feedback: InkRipple via Material widgets only.

## French UI copy tone

- Tutoiement is forbidden; use **vous** in every message.
- Short, concrete verbs: « Ajouter une carte », « Rembourser », « Vérifier ».
- Errors explain how to fix: « Solde insuffisant : rechargez votre portefeuille ou payez par carte. »
- Numbers/dates: `fr_FR` formats via `intl`, currency `€` symbol.

## Screen review checklist (run through every time)

1. Theme tokens only — no hardcoded hex in feature code (hue via AppColors).
2. Contrast rules respected (accent/warning → dark text; small text → Strong).
3. French, vouvoiement, `intl` formats for dates/money.
4. 48 dp min touch targets, tappable cards have semantic labels.
5. 8-pt rhythm: paddings/margins stick to spacing tokens.
6. Visual hierarchy: one bold hero per screen, one accent action max.
