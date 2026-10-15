import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:test/test.dart';

void main() {
  group('TeledocCallRoom', () {
    test('accepte le format généré par le serveur', () {
      expect(
        TeledocCallRoom.isValid(
            'ProxiLifeTeleDoc0123456789abcdef0123456789abcdef'),
        isTrue,
      );
    });

    test('refuse tout ce qui pourrait détourner l\'URL', () {
      for (final room in [
        null,
        '',
        'ProxiLifeTeleDoc',
        'ProxiLifeTeleDoc0123', // trop court : devinable
        'ProxiLifeTeleDoc0123456789ABCDEF0123456789ABCDEF', // majuscules
        'ProxiLifeTeleDoc0123456789abcdef0123456789abcdef/../x',
        'ProxiLifeTeleDoc0123456789abcdef0123456789abcdef#config',
        'AutreSalle0123456789abcdef0123456789abcdef',
      ]) {
        expect(TeledocCallRoom.isValid(room), isFalse, reason: '$room');
      }
    });
  });

  test('les DTO transportent la salle d\'appel (aller-retour JSON)', () {
    const room = 'ProxiLifeTeleDoc0123456789abcdef0123456789abcdef';
    final consultation = TeledocConsultationDto.fromJson({
      'id': 1,
      'date_debut': '2026-10-15T09:00:00',
      'type': 'video',
      'id_demande': 2,
      'motif': 'Fièvre',
      'urgence': 'moyenne',
      'statut_demande': 'en_cours',
      'salle_appel': room,
    });
    expect(consultation.salleAppel, room);
    expect(consultation.toJson()['salle_appel'], room);

    final status = TeledocQueueStatusDto.fromJson(
        {'id_demande': 2, 'statut': 'en_cours', 'salle_appel': room});
    expect(status.salleAppel, room);
    expect(status.toJson()['salle_appel'], room);
  });
}
