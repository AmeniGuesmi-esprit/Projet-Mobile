import 'dart:convert';

import 'package:proxilife_shared/proxilife_shared.dart';

/// Opens a link outside the app: Jitsi Meet (app or browser) for the call,
/// a maps app for the itinerary. Faked in tests.
abstract class TeledocLinkOpener {
  /// Returns false if no app could open [uri].
  Future<bool> open(Uri uri);
}

/// Builds the Jitsi Meet link of a consultation (CONCEPTION.md, D34–D35).
abstract final class TeledocCallLink {
  /// Jitsi instance; `--dart-define=TELEDOC_JITSI_URL=https://…` points the
  /// app to another (e.g. self-hosted) instance without code change.
  static const String defaultBaseUrl = String.fromEnvironment(
    'TELEDOC_JITSI_URL',
    defaultValue: 'https://meet.jit.si',
  );

  /// `null` if [room] is not a server-generated room or [baseUrl] is not an
  /// HTTPS URL: nothing else may end up in the link.
  static Uri? build({
    required String? room,
    required TeledocConsultationType type,
    String? displayName,
    String baseUrl = defaultBaseUrl,
  }) {
    if (!TeledocCallRoom.isValid(room)) return null;
    final base = Uri.tryParse(baseUrl);
    if (base == null || base.scheme != 'https' || base.host.isEmpty) {
      return null;
    }
    final name = displayName?.trim() ?? '';
    // Jitsi reads its options from the fragment (never sent to the server);
    // values are JSON.
    final options = [
      // Pre-join screen: camera / micro check before entering.
      'config.prejoinConfig.enabled=true',
      // Join in the browser when the Jitsi app is not installed.
      'config.disableDeepLinking=true',
      if (type == TeledocConsultationType.audio)
        'config.startWithVideoMuted=true',
      if (name.isNotEmpty)
        'userInfo.displayName=${Uri.encodeComponent(jsonEncode(name))}',
    ];
    final path = base.path.endsWith('/') ? base.path : '${base.path}/';
    return base.replace(path: '$path$room', fragment: options.join('&'));
  }
}
