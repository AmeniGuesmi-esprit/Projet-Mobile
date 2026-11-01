/// Input validators shared by the app (UX-level feedback) and the server
/// (authoritative checks). All validation rules live here — never duplicate
/// them.
library;

/// Basic but strict-enough e-mail check (RFC 5322 lite).
bool isValidEmail(String email) {
  final trimmed = email.trim();
  if (trimmed.isEmpty || trimmed.length > 254) return false;
  final pattern = RegExp(r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@"
      r'([A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\.)+'
      r'[A-Za-z]{2,}$');
  return pattern.hasMatch(trimmed);
}

String normalizeEmail(String email) => email.trim().toLowerCase();

/// Password policy: at least 8 chars, one lowercase, one uppercase, one digit.
String? passwordPolicyError(String password) {
  if (password.length < 8) {
    return 'Le mot de passe doit contenir au moins 8 caractères';
  }
  if (!RegExp(r'[a-z]').hasMatch(password)) {
    return 'Le mot de passe doit contenir une minuscule';
  }
  if (!RegExp(r'[A-Z]').hasMatch(password)) {
    return 'Le mot de passe doit contenir une majuscule';
  }
  if (!RegExp(r'[0-9]').hasMatch(password)) {
    return 'Le mot de passe doit contenir un chiffre';
  }
  return null;
}

/// French (mobile or landline) and Tunisian phone numbers, with or without
/// international prefix (+33 / 0033, +216 / 00216).
bool isValidPhone(String phone) {
  final compact = phone.replaceAll(RegExp(r'[\s.\-()]'), '');
  final french = RegExp(r'^(?:\+33|0033|0)[1-9]\d{8}$');
  // Tunisie : 8 chiffres commençant par 2-9, préfixe optionnel.
  final tunisian = RegExp(r'^(?:\+216|00216)?[2-9]\d{7}$');
  return french.hasMatch(compact) || tunisian.hasMatch(compact);
}

/// Luhn check for card numbers. Input may contain spaces.
bool isValidCardNumber(String cardNumber) {
  final digits = cardNumber.replaceAll(RegExp(r'\s'), '');
  if (!RegExp(r'^\d{12,19}$').hasMatch(digits)) return false;
  var sum = 0;
  var alternate = false;
  for (var i = digits.length - 1; i >= 0; i--) {
    var n = digits.codeUnitAt(i) - 0x30;
    if (alternate) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    sum += n;
    alternate = !alternate;
  }
  return sum % 10 == 0;
}

String last4OfCard(String cardNumber) {
  final digits = cardNumber.replaceAll(RegExp(r'\s'), '');
  return digits.substring(digits.length - 4);
}

/// Card expiry in `MM/YY` form, not in the past.
bool isValidCardExpiry(String expiry, {DateTime? now}) {
  final match = RegExp(r'^(\d{2})/(\d{2})$').firstMatch(expiry.trim());
  if (match == null) return false;
  final month = int.tryParse(match.group(1)!) ?? 0;
  final year = 2000 + (int.tryParse(match.group(2)!) ?? -1);
  if (month < 1 || month > 12) return false;
  final reference = now ?? DateTime.now();
  final expiresAfter = DateTime(year, month + 1, 1);
  return expiresAfter.isAfter(reference);
}

// ---------------------------------------------------------------------------
// French RIB
// ---------------------------------------------------------------------------

/// Letter-to-digit substitution table for French RIB keys.
const Map<String, String> _ribLetterDigits = {
  'A': '1', 'J': '1',
  'B': '2', 'K': '2', 'S': '2',
  'C': '3', 'L': '3', 'T': '3',
  'D': '4', 'M': '4', 'U': '4',
  'E': '5', 'N': '5', 'V': '5',
  'F': '6', 'O': '6', 'W': '6',
  'G': '7', 'P': '7', 'X': '7',
  'H': '8', 'Q': '8', 'Y': '8',
  'I': '9', 'R': '9', 'Z': '9',
};

String normalizeRib(String rib) =>
    rib.toUpperCase().replaceAll(RegExp(r'\s'), '');

String? _ribToDigits(String rib) {
  final buffer = StringBuffer();
  for (final unit in rib.codeUnits) {
    final char = String.fromCharCode(unit);
    if (RegExp(r'^[0-9]$').hasMatch(char)) {
      buffer.write(char);
    } else if (_ribLetterDigits.containsKey(char)) {
      buffer.write(_ribLetterDigits[char]);
    } else {
      return null;
    }
  }
  return buffer.toString();
}

/// Computes the expected RIB key for [bank] (5 digits), [branch] (5 digits)
/// and [account] (11 alphanumeric chars). Key = 97 − ((89·bank + 15·branch +
/// 3·account) % 97).
String? computeRibKey(String bank, String branch, String account) {
  final bankDigits = _ribToDigits(bank);
  final branchDigits = _ribToDigits(branch);
  final accountDigits = _ribToDigits(account);
  if (bankDigits == null || branchDigits == null || accountDigits == null) {
    return null;
  }
  if (!RegExp(r'^\d{5}$').hasMatch(bankDigits) ||
      !RegExp(r'^\d{5}$').hasMatch(branchDigits) ||
      !RegExp(r'^\d{11}$').hasMatch(accountDigits)) {
    return null;
  }
  final bankValue = int.parse(bankDigits);
  final branchValue = int.parse(branchDigits);
  final accountValue = int.parse(accountDigits);
  final key = 97 - ((89 * bankValue + 15 * branchValue + 3 * accountValue) % 97);
  return key.toString().padLeft(2, '0');
}

/// Validates a full French RIB (23 alphanumeric chars, spaces ignored).
bool isValidRib(String rib) {
  final compact = normalizeRib(rib);
  if (!RegExp(r'^[0-9A-Z]{23}$').hasMatch(compact)) return false;
  final bank = compact.substring(0, 5);
  final branch = compact.substring(5, 10);
  final account = compact.substring(10, 21);
  final declaredKey = compact.substring(21, 23);
  if (!RegExp(r'^\d{2}$').hasMatch(declaredKey)) return false;
  return computeRibKey(bank, branch, account) == declaredKey;
}

/// Groups a RIB in 4-char blocks for display.
String formatRib(String rib) {
  final compact = normalizeRib(rib);
  final buffer = StringBuffer();
  for (var i = 0; i < compact.length; i += 4) {
    if (i > 0) buffer.write(' ');
    final end = (i + 4 > compact.length) ? compact.length : i + 4;
    buffer.write(compact.substring(i, end));
  }
  return buffer.toString();
}

/// Non-empty human name: letters, spaces, hyphens, apostrophes, accents.
bool isValidName(String name) {
  final trimmed = name.trim();
  if (trimmed.length < 2 || trimmed.length > 60) return false;
  return RegExp(r"^[\p{L}\s'\-]+$", unicode: true).hasMatch(trimmed);
}

/// Positive amount in whole cents, capped to avoid absurd inputs.
bool isValidAmountCents(int cents, {int maxCents = 100000000}) =>
    cents > 0 && cents <= maxCents;
