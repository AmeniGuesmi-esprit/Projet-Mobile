import 'package:proxilife_shared/proxilife_shared.dart';

/// A GPS position (WGS 84).
class TeledocPosition {
  const TeledocPosition(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

/// Why the device position could not be read.
enum TeledocLocationIssue {
  serviceDisabled('La localisation du téléphone est désactivée.'),
  denied('Vous avez refusé l\'accès à votre position.'),
  deniedForever(
    'L\'accès à votre position est bloqué : autorisez-le dans les réglages.',
  ),
  unavailable('Votre position n\'a pas pu être déterminée.');

  const TeledocLocationIssue(this.message);

  /// User-facing French explanation.
  final String message;
}

class TeledocLocationException implements Exception {
  const TeledocLocationException(this.issue);

  final TeledocLocationIssue issue;

  @override
  String toString() => 'TeledocLocationException(${issue.name})';
}

/// Device position, as seen by the presentation layer (faked in tests).
abstract class TeledocLocationProvider {
  /// Asks for the permission if needed. Throws [TeledocLocationException].
  Future<TeledocPosition> current();

  /// Opens the system screen that fixes [issue] (location or app settings).
  Future<void> openSettings(TeledocLocationIssue issue);
}

/// Fallback when the position is unknown: the search still works, from the
/// centre of Tunis (where the demo pharmacies are), and the screen says so.
const TeledocPosition teledocTunisCentre = TeledocPosition(36.8065, 10.1815);

/// External links of a pharmacy (opened with a `TeledocLinkOpener`).
abstract final class TeledocPharmacyLinks {
  /// `geo:` lets the user pick any maps / navigation app installed.
  static Uri mapsApp(TeledocPharmacyDto pharmacy) {
    final at = '${pharmacy.latitude},${pharmacy.longitude}';
    return Uri.parse('geo:$at?q=$at(${Uri.encodeComponent(pharmacy.nom)})');
  }

  /// Fallback in the browser: OpenStreetMap routing, no API key.
  static Uri webDirections(TeledocPosition from, TeledocPharmacyDto to) =>
      Uri.https('www.openstreetmap.org', '/directions', {
        'engine': 'fossgis_osrm_car',
        'route':
            '${from.latitude},${from.longitude};'
            '${to.latitude},${to.longitude}',
      });

  /// `tel:` link (dialer opens pre-filled, no CALL_PHONE permission needed).
  static Uri phone(String telephone) =>
      Uri(scheme: 'tel', path: telephone.replaceAll(RegExp(r'[^0-9+]'), ''));
}
