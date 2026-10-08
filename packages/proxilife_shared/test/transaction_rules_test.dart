import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:test/test.dart';

void main() {
  group('TransactionRules.canTransition', () {
    test('en_attente -> paye / echoue only', () {
      expect(
        TransactionRules.canTransition(
            TransactionStatus.enAttente, TransactionStatus.paye),
        isTrue,
      );
      expect(
        TransactionRules.canTransition(
            TransactionStatus.enAttente, TransactionStatus.echoue),
        isTrue,
      );
      expect(
        TransactionRules.canTransition(
            TransactionStatus.enAttente, TransactionStatus.rembourse),
        isFalse,
      );
      expect(
        TransactionRules.canTransition(
            TransactionStatus.enAttente, TransactionStatus.enAttente),
        isFalse,
      );
    });

    test('paye -> rembourse only', () {
      expect(
        TransactionRules.canTransition(
            TransactionStatus.paye, TransactionStatus.rembourse),
        isTrue,
      );
      expect(
        TransactionRules.canTransition(
            TransactionStatus.paye, TransactionStatus.enAttente),
        isFalse,
      );
      expect(
        TransactionRules.canTransition(
            TransactionStatus.paye, TransactionStatus.echoue),
        isFalse,
      );
    });

    test('terminal states accept no transition', () {
      for (final target in TransactionStatus.values) {
        expect(
          TransactionRules.canTransition(TransactionStatus.echoue, target),
          isFalse,
        );
        expect(
          TransactionRules.canTransition(TransactionStatus.rembourse, target),
          isFalse,
        );
      }
    });
  });

  group('cancel / refund helpers', () {
    test('only pending transactions are cancellable', () {
      expect(TransactionRules.canCancel(TransactionStatus.enAttente), isTrue);
      expect(TransactionRules.canCancel(TransactionStatus.paye), isFalse);
      expect(TransactionRules.canCancel(TransactionStatus.rembourse), isFalse);
    });

    test('only paid transactions are refundable', () {
      expect(TransactionRules.canRefund(TransactionStatus.paye), isTrue);
      expect(TransactionRules.canRefund(TransactionStatus.enAttente), isFalse);
      expect(TransactionRules.canRefund(TransactionStatus.echoue), isFalse);
    });
  });

  group('DTO round-trips', () {
    test('UserDto', () {
      final dto = UserDto.fromJson(const {
        'id': 7,
        'nom': 'Guesmi',
        'prenom': 'Ameni',
        'email': 'client@proxilife.fr',
        'telephone': '0612345678',
        'photo': null,
        'role': 'client',
        'statut_compte': 'actif',
        'rib_masque': null,
        'solde_centimes': 5000,
      });
      expect(dto.id, 7);
      expect(dto.role, UserRole.client);
      expect(dto.toJson()['statut_compte'], 'actif');
      expect(dto.nomComplet, 'Ameni Guesmi');
    });

    test('PaymentMethodDto', () {
      final dto = PaymentMethodDto.fromJson(const {
        'id': 3,
        'type': 'carte_bancaire',
        'quatre_derniers_chiffres': '6467',
        'nom_titulaire': 'AMENI GUESMI',
        'date_expiration': '10/29',
        'par_defaut': true,
      });
      expect(dto.type, PaymentMethodType.carteBancaire);
      expect(dto.parDefaut, isTrue);
      expect(dto.toJson()['quatre_derniers_chiffres'], '6467');
    });

    test('TransactionDto', () {
      final dto = TransactionDto.fromJson(const {
        'id': 42,
        'montant_centimes': 2599,
        'devise': 'EUR',
        'date': '2026-10-08T12:00:00.000',
        'statut': 'paye',
        'type_service': 'EcoRoute',
        'id_reference': 'TRIP-93',
        'facture_numero': 'FAC-2026-000042',
        'id_moyen_paiement': 3,
        'beneficiaire_nom': 'Fawzi Saidi',
        'beneficiaire_email': 'conducteur@proxilife.fr',
      });
      expect(dto.statut, TransactionStatus.paye);
      expect(dto.typeService, ServiceType.ecoRoute);
      expect(dto.montantCentimes, 2599);
      expect(dto.toJson()['facture_numero'], 'FAC-2026-000042');
    });
  });
}
