import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/teledoc_call.dart';

/// [TeledocLinkOpener] backed by `url_launcher`: the link is handed to
/// Android, which opens the Jitsi Meet app if installed (App Links),
/// otherwise the browser. ProxiLife itself never captures camera or micro.
class UrlLauncherLinkOpener implements TeledocLinkOpener {
  const UrlLauncherLinkOpener();

  @override
  Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      return false;
    }
  }
}
