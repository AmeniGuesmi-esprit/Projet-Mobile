import 'package:flutter/material.dart';

import '../../core/location/device_location_service.dart';

/// Current GPS position, after explaining why it is needed when the system
/// permission has not been granted yet. Null when unavailable or refused;
/// the reason is shown to the user.
Future<({double latitude, double longitude})?> locateWithConsent(
  BuildContext context,
  String reason,
) async {
  const location = DeviceLocationService();
  try {
    if (await location.needsPermissionPrompt()) {
      if (!context.mounted) return null;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Utiliser votre position ?'),
          content: Text(reason),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Plus tard'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Continuer'),
            ),
          ],
        ),
      );
      if (accepted != true) return null;
      await location.requestPermission();
    }
    return await location.currentPosition();
  } on LocationException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
    return null;
  }
}
