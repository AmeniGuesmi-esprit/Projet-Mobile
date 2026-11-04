import 'dart:convert';

/// Content id of the inline QR image (`<img src="cid:...">`).
const String reservationQrCid = 'qr-retrait@proxilife';

/// Everything the "Votre QR code de retrait" e-mail needs. Built by the
/// FoodSave reservation service once the payment is confirmed.
class ReservationQrEmail {
  const ReservationQrEmail({
    required this.to,
    required this.prenom,
    required this.reservationId,
    required this.basketTitle,
    required this.storeName,
    required this.storeAddress,
    required this.quantity,
    required this.amountCents,
    required this.pickupStart,
    required this.pickupEnd,
    required this.qrExpiry,
    required this.qrToken,
    this.cashAtPickup = false,
  });

  final String to;
  final String prenom;
  final int reservationId;
  final String basketTitle;
  final String storeName;
  final String storeAddress;
  final int quantity;
  final int amountCents;
  final DateTime pickupStart;
  final DateTime pickupEnd;
  final DateTime qrExpiry;

  /// Signed token encoded in the QR (`FS1.<id>.<nonce>.<sig>`).
  final String qrToken;

  /// Cash ("espèces"): the client pays the merchant at pickup.
  final bool cashAtPickup;

  String get _status => cashAtPickup
      ? 'confirmée (paiement en espèces au retrait)'
      : 'confirmée et payée';

  String get _amountRowLabel =>
      cashAtPickup ? 'À payer au retrait' : 'Montant';

  String get reference => 'FS-$reservationId';

  String get subject => 'Votre QR code de retrait FoodSave — Réf. $reference';

  String get pickupWindow {
    final s = pickupStart.toLocal();
    final e = pickupEnd.toLocal();
    final sameDay = s.year == e.year && s.month == e.month && s.day == e.day;
    return sameDay
        ? '${_dayFr(s)}, ${_clock(s)} – ${_clock(e)}'
        : '${_dayFr(s)} ${_clock(s)} – ${_dayFr(e)} ${_clock(e)}';
  }

  String get expiryLabel {
    final x = qrExpiry.toLocal();
    return '${_dayFr(x)} à ${_clock(x)}';
  }

  String get amountLabel => formatDinars(amountCents);

  String get quantityLabel => quantity == 1 ? '1 panier' : '$quantity paniers';

  String get text => 'Bonjour $prenom,\n\n'
      'Votre réservation FoodSave est $_status.\n\n'
      'Panier   : $basketTitle ($quantityLabel)\n'
      'Commerce : $storeName — $storeAddress\n'
      'Retrait  : $pickupWindow\n'
      '${cashAtPickup ? 'À payer  : $amountLabel en espèces au retrait' : 'Montant  : $amountLabel'}\n'
      'Référence: $reference\n\n'
      'Présentez le QR code joint à cet e-mail (ou celui de l\'application '
      'ProxiLife) au commerçant pendant le créneau de retrait.\n'
      'Il est valable jusqu\'au $expiryLabel.\n\n'
      'Merci de sauver un panier du gaspillage !\n'
      'L\'équipe ProxiLife';

  String get html {
    final e = const HtmlEscape();
    String row(String label, String value, {bool strong = false}) => '''
<tr>
  <td style="padding:6px 0;color:#4F5E58;font-size:13px;width:110px;vertical-align:top">$label</td>
  <td style="padding:6px 0;color:#1F2933;font-size:14px;${strong ? 'font-weight:700;' : ''}">$value</td>
</tr>''';
    return '''
<!doctype html>
<html lang="fr">
<body style="margin:0;padding:0;background:#F5F8F6;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#F5F8F6;padding:24px 12px">
<tr><td align="center">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background:#FFFFFF;border-radius:16px;overflow:hidden;border:1px solid #E9EFEC">
  <tr>
    <td style="background:#A3520D;padding:22px 24px;color:#FFFFFF">
      <div style="font-size:13px;letter-spacing:1px;text-transform:uppercase;opacity:.9">ProxiLife · FoodSave</div>
      <div style="font-size:22px;font-weight:700;margin-top:4px">Réservation confirmée</div>
    </td>
  </tr>
  <tr>
    <td style="padding:24px 24px 8px;color:#1F2933;font-size:15px;line-height:1.5">
      Bonjour ${e.convert(prenom)},<br>
      votre réservation est ${e.convert(_status)}. Présentez ce QR code au commerçant
      pendant le créneau de retrait.
    </td>
  </tr>
  <tr>
    <td align="center" style="padding:16px 24px 8px">
      <table role="presentation" cellpadding="0" cellspacing="0" style="background:#FFF3E8;border-radius:16px">
        <tr><td style="padding:16px">
          <img src="cid:$reservationQrCid" width="232" height="232" alt="QR code de retrait ${e.convert(reference)}"
               style="display:block;width:232px;height:232px;border-radius:8px;background:#FFFFFF">
        </td></tr>
      </table>
      <div style="margin-top:12px;font-size:13px;color:#4F5E58">Réf. <strong style="color:#1F2933">${e.convert(reference)}</strong></div>
      <div style="display:inline-block;margin-top:10px;padding:6px 12px;border-radius:999px;background:#FDF1D8;color:#1F2933;font-size:13px">
        Valable jusqu'au <strong>${e.convert(expiryLabel)}</strong>
      </div>
    </td>
  </tr>
  <tr>
    <td style="padding:16px 24px 8px">
      <div style="border-top:2px dashed #E9EFEC"></div>
    </td>
  </tr>
  <tr>
    <td style="padding:8px 24px 16px">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
        ${row('Panier', '${e.convert(basketTitle)} <span style="color:#4F5E58">(${e.convert(quantityLabel)})</span>', strong: true)}
        ${row('Commerce', '${e.convert(storeName)}<br><span style="color:#4F5E58;font-size:13px">${e.convert(storeAddress)}</span>')}
        ${row('Retrait', e.convert(pickupWindow))}
        ${row(_amountRowLabel, e.convert(amountLabel), strong: true)}
      </table>
    </td>
  </tr>
  <tr>
    <td style="padding:0 24px 24px;color:#4F5E58;font-size:12px;line-height:1.5">
      Astuce : augmentez la luminosité de votre écran pour faciliter le scan.
      Le QR code est aussi disponible dans l'application ProxiLife, rubrique
      « Mes réservations ».
    </td>
  </tr>
  <tr>
    <td style="background:#F5F8F6;padding:14px 24px;color:#6B7A75;font-size:12px;text-align:center">
      Merci de sauver un panier du gaspillage 🌱 — L'équipe ProxiLife
    </td>
  </tr>
</table>
</td></tr>
</table>
</body>
</html>''';
  }
}

/// Whole cents → "45,000 DT" (3 decimals, like the app's `fr_TN` format).
String formatDinars(int cents) {
  final negative = cents < 0;
  final abs = cents.abs();
  final whole = abs ~/ 100;
  final fraction = (abs % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}$whole,${fraction}0 DT';
}

const _weekdays = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche'
];
const _months = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre'
];

String _dayFr(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

String _clock(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';
