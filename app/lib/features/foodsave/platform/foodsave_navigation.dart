import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/session/session_controller.dart';
import '../client/basket_detail_screen.dart';
import '../client/reservation_qr_screen.dart';
import '../merchant/merchant_basket_detail_screen.dart';
import '../merchant/merchant_reservations_screen.dart';
import 'foodsave_notifications_screen.dart';

/// Root navigator of the app (set on MaterialApp) so notification taps can
/// open a screen from outside the widget tree.
final GlobalKey<NavigatorState> appNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'appNavigator');

/// Payload carried by a local notification for [n]:
/// `reservation:<id>`, `basket:<id>` or `foodsave` (notification list).
String foodSavePayloadFor(FoodSaveNotificationDto n) {
  if (n.reservationId != null) return 'reservation:${n.reservationId}';
  if (n.panierId != null) return 'basket:${n.panierId}';
  return 'foodsave';
}

/// Screen to open for [payload], depending on the user's role. Null when
/// the payload is not a FoodSave one.
Widget? foodSaveScreenForPayload(String payload, SessionController session) {
  final merchant = session.user?.role == UserRole.commercant;
  if (payload == 'foodsave') {
    return FoodSaveNotificationsScreen(session: session);
  }
  final parts = payload.split(':');
  if (parts.length != 2) return null;
  final id = int.tryParse(parts[1]);
  if (id == null) return null;
  switch (parts[0]) {
    case 'basket':
      return merchant
          ? MerchantBasketDetailScreen(session: session, basketId: id)
          : BasketDetailScreen(session: session, basketId: id);
    case 'reservation':
      return merchant
          ? MerchantReservationsScreen(session: session)
          : ReservationQrScreen(session: session, reservationId: id);
  }
  return null;
}

/// Opens the target of a tapped notification on [appNavigatorKey].
/// Ignored when signed out or when the payload is unknown.
void openFoodSavePayload(String payload, SessionController session) {
  if (session.status != SessionStatus.authenticated || session.user == null) {
    return;
  }
  final screen = foodSaveScreenForPayload(payload, session);
  final navigator = appNavigatorKey.currentState;
  if (screen == null || navigator == null) return;
  navigator.push(MaterialPageRoute<void>(builder: (_) => screen));
}
