import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:test/test.dart';

void main() {
  group('isValidEmail', () {
    test('accepts common valid addresses', () {
      expect(isValidEmail('client@proxilife.fr'), isTrue);
      expect(isValidEmail('a.b+c@sub.domain.co'), isTrue);
      expect(isValidEmail('  client@proxilife.fr '), isTrue);
    });

    test('rejects invalid addresses', () {
      expect(isValidEmail(''), isFalse);
      expect(isValidEmail('notanemail'), isFalse);
      expect(isValidEmail('a@b'), isFalse);
      expect(isValidEmail('a @b.fr'), isFalse);
      expect(isValidEmail('@b.fr'), isFalse);
    });
  });

  group('passwordPolicyError', () {
    test('accepts a strong password', () {
      expect(passwordPolicyError('Proxilife2026!'), isNull);
    });

    test('rejects weak passwords', () {
      expect(passwordPolicyError('short1A'), isNotNull);
      expect(passwordPolicyError('alllowercase1'), isNotNull);
      expect(passwordPolicyError('ALLUPPER1'), isNotNull);
      expect(passwordPolicyError('NoDigitsHere'), isNotNull);
    });
  });

  group('isValidPhone', () {
    test('accepts French formats', () {
      expect(isValidPhone('0612345678'), isTrue);
      expect(isValidPhone('06 12 34 56 78'), isTrue);
      expect(isValidPhone('+33612345678'), isTrue);
      expect(isValidPhone('0033612345678'), isTrue);
    });

    test('accepts Tunisian formats', () {
      expect(isValidPhone('98123456'), isTrue);
      expect(isValidPhone('20 123 456'), isTrue);
      expect(isValidPhone('+21698123456'), isTrue);
      expect(isValidPhone('+216 98 123 456'), isTrue);
      expect(isValidPhone('0021698123456'), isTrue);
      expect(isValidPhone('55123456'), isTrue);
      expect(isValidPhone('71234567'), isTrue);
    });

    test('rejects invalid numbers', () {
      expect(isValidPhone('123'), isFalse);
      expect(isValidPhone('06123456789'), isFalse);
      expect(isValidPhone('+115551234567'), isFalse);
      expect(isValidPhone('08123456'), isFalse); // TN must start 2-9 (nor 1 nor 0)
      expect(isValidPhone('+216981234567'), isFalse);
      expect(isValidPhone('981234567'), isFalse);
    });
  });

  group('Luhn / cards', () {
    test('accepts valid card numbers', () {
      expect(isValidCardNumber('4539 1488 0343 6467'), isTrue);
      expect(isValidCardNumber('4485275742308327'), isTrue);
    });

    test('rejects invalid card numbers', () {
      expect(isValidCardNumber('4539 1488 0343 6468'), isFalse);
      expect(isValidCardNumber('123'), isFalse);
      expect(isValidCardNumber(''), isFalse);
    });

    test('last4OfCard returns the last 4 digits', () {
      expect(last4OfCard('4539 1488 0343 6467'), '6467');
    });

    test('isValidCardExpiry checks format and past dates', () {
      final now = DateTime(2026, 10, 8);
      expect(isValidCardExpiry('10/29', now: now), isTrue);
      expect(isValidCardExpiry('10/26', now: now), isTrue);
      expect(isValidCardExpiry('09/26', now: now), isFalse);
      expect(isValidCardExpiry('13/26', now: now), isFalse);
      expect(isValidCardExpiry('1026', now: now), isFalse);
    });
  });

  group('RIB', () {
    // Valid RIBs computed with the official French key formula.
    const rib1 = '30004000011234567890173';
    const rib2 = '20041010055000000000085';

    test('accepts valid RIBs with or without spaces', () {
      expect(isValidRib(rib1), isTrue);
      expect(isValidRib(rib2), isTrue);
      expect(isValidRib('30004 00001 12345678901 73'), isTrue);
      expect(isValidRib(rib1.toLowerCase()), isTrue);
    });

    test('rejects wrong key or wrong length', () {
      expect(isValidRib('30004000011234567890174'), isFalse);
      expect(isValidRib('30004'), isFalse);
      expect(isValidRib(''), isFalse);
      expect(isValidRib('${rib1}0'), isFalse);
      expect(isValidRib('3000400001123456789017'), isFalse);
    });

    test('computeRibKey matches known values', () {
      expect(computeRibKey('30004', '00001', '12345678901'), '73');
      expect(computeRibKey('20041', '01005', '50000000000'), '85');
    });

    test('formatRib groups by 4 characters', () {
      expect(formatRib(rib1), '3000 4000 0112 3456 7890 173');
    });
  });

  group('isValidName', () {
    test('accepts accented names', () {
      expect(isValidName('Ameni'), isTrue);
      expect(isValidName('Jean-Luc'), isTrue);
      expect(isValidName("L'Ecole"), isTrue);
    });

    test('rejects names that are too short or contain digits', () {
      expect(isValidName('A'), isFalse);
      expect(isValidName('R2D2'), isFalse);
      expect(isValidName(''), isFalse);
    });
  });

  group('isValidAmountCents', () {
    test('accepts positive amounts', () {
      expect(isValidAmountCents(1), isTrue);
      expect(isValidAmountCents(2599), isTrue);
    });

    test('rejects zero, negative and absurd amounts', () {
      expect(isValidAmountCents(0), isFalse);
      expect(isValidAmountCents(-5), isFalse);
      expect(isValidAmountCents(100000001), isFalse);
    });
  });
}
