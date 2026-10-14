import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:test/test.dart';

void main() {
  const attente = TeledocRequestStatus.enAttente;
  const enCours = TeledocRequestStatus.enCours;
  const terminee = TeledocRequestStatus.terminee;
  const annulee = TeledocRequestStatus.annulee;
  const patient = TeledocActor.patient;
  const medecin = TeledocActor.medecin;

  group('TeledocRequestRules.canTransition', () {
    test('le médecin démarre une demande en attente', () {
      expect(TeledocRequestRules.canTransition(attente, enCours, medecin),
          isTrue);
      expect(TeledocRequestRules.canTransition(attente, enCours, patient),
          isFalse);
    });

    test('seul le patient annule une demande en attente', () {
      expect(TeledocRequestRules.canTransition(attente, annulee, patient),
          isTrue);
      expect(TeledocRequestRules.canTransition(attente, annulee, medecin),
          isFalse);
    });

    test('seul le médecin termine, annule ou remet en file une consultation '
        'en cours', () {
      for (final target in [terminee, annulee, attente]) {
        expect(TeledocRequestRules.canTransition(enCours, target, medecin),
            isTrue,
            reason: 'en_cours → ${target.apiValue}');
        expect(TeledocRequestRules.canTransition(enCours, target, patient),
            isFalse,
            reason: 'patient : en_cours → ${target.apiValue}');
      }
    });

    test('on ne peut pas sauter d\'étape', () {
      expect(TeledocRequestRules.canTransition(attente, terminee, medecin),
          isFalse);
    });

    test('les états terminaux sont figés', () {
      for (final from in [terminee, annulee]) {
        for (final to in TeledocRequestStatus.values) {
          for (final actor in TeledocActor.values) {
            expect(TeledocRequestRules.canTransition(from, to, actor), isFalse);
          }
        }
        expect(TeledocRequestRules.isTerminal(from), isTrue);
      }
      expect(TeledocRequestRules.isTerminal(attente), isFalse);
      expect(TeledocRequestRules.isTerminal(enCours), isFalse);
    });
  });

  test('modification autorisée seulement en attente', () {
    expect(TeledocRequestRules.canEdit(attente), isTrue);
    for (final s in [enCours, terminee, annulee]) {
      expect(TeledocRequestRules.canEdit(s), isFalse);
    }
  });

  test('une demande est active en attente ou en cours', () {
    expect(TeledocRequestRules.isActive(attente), isTrue);
    expect(TeledocRequestRules.isActive(enCours), isTrue);
    expect(TeledocRequestRules.isActive(terminee), isFalse);
    expect(TeledocRequestRules.isActive(annulee), isFalse);
  });

  test('parse rejette les valeurs inconnues', () {
    expect(TeledocRequestStatus.parse('en_cours'), enCours);
    expect(() => TeledocRequestStatus.parse('ouverte'), throwsArgumentError);
    expect(() => TeledocUrgency.parse('critique'), throwsArgumentError);
    expect(() => TeledocConsultationType.parse('chat'), throwsArgumentError);
  });
}
