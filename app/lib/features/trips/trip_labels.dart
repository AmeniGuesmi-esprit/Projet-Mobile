import 'package:proxilife_shared/proxilife_shared.dart';

/// French labels for the carpooling enums (UI only).
extension AmbianceLabel on Ambiance {
  String get label => switch (this) {
        Ambiance.discussion => 'Discussion',
        Ambiance.silence => 'Silence',
        Ambiance.indifferent => 'Peu importe',
      };
}

extension TripStatusLabel on TripStatus {
  String get label => switch (this) {
        TripStatus.ouvert => 'Ouvert',
        TripStatus.complet => 'Complet',
        TripStatus.termine => 'Terminé',
        TripStatus.annule => 'Annulé',
      };
}

String _two(int n) => n.toString().padLeft(2, '0');

/// "30/10/2026"
String formatTripDate(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

/// "08:49"
String formatTripTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';
