import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/session/session_controller.dart';
import '../../../core/theme/app_colors.dart';
import 'booking/reserve_sheet.dart';

const double _sheetRadius = 28;

/// Full reservation flow for [basket] (quantity → payment method → confirm →
/// QR). Returns the created reservation, or null if the user backed out.
Future<ReservationDto?> showReserveFlow(
  BuildContext context, {
  required SessionController session,
  required BasketDto basket,
}) =>
    showModalBottomSheet<ReservationDto>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(_sheetRadius)),
      ),
      builder: (_) => ReserveSheet(session: session, basket: basket),
    );
