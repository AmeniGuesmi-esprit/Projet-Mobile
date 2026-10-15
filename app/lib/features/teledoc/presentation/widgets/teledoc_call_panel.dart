import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/teledoc_call.dart';
import 'teledoc_async_view.dart';

/// "Rejoindre l'appel" block shared by the patient and the doctor screens.
///
/// The call runs in Jitsi Meet (app or browser, D34): that app asks for the
/// camera / micro permissions, so ProxiLife does not request them (D35).
class TeledocCallPanel extends StatelessWidget {
  const TeledocCallPanel({
    super.key,
    required this.room,
    required this.type,
    required this.opener,
    this.displayName,
    this.isDoctor = false,
    this.trailing,
    this.details = const [],
  });

  final String? room;
  final TeledocConsultationType type;
  final TeledocLinkOpener opener;
  final String? displayName;

  /// The doctor opens the room (moderator on meet.jit.si).
  final bool isDoctor;
  final Widget? trailing;
  final List<Widget> details;

  bool get _video => type == TeledocConsultationType.video;

  Uri? get _link =>
      TeledocCallLink.build(room: room, type: type, displayName: displayName);

  Future<void> _copy(BuildContext context, Uri link) async {
    await Clipboard.setData(ClipboardData(text: link.toString()));
    if (context.mounted) showTeledocSnack(context, 'Lien de l\'appel copié');
  }

  Future<void> _join(BuildContext context, Uri link) async {
    final opened = await opener.open(link);
    if (opened || !context.mounted) return;
    showTeledocSnack(
      context,
      'Impossible d\'ouvrir l\'appel sur cet appareil',
      actionLabel: 'Copier le lien',
      onAction: () => _copy(context, link),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = _link;
    return TeledocSection(
      title: _video ? 'Appel vidéo' : 'Appel audio',
      trailing: trailing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...details,
          if (details.isNotEmpty) const SizedBox(height: AppSpacing.sm),
          if (link == null)
            Text(
              'Salle d\'appel indisponible : actualisez l\'écran.',
              style: theme.textTheme.bodyMedium,
            )
          else ...[
            FilledButton.icon(
              onPressed: () => _join(context, link),
              icon: Icon(_video ? Icons.videocam : Icons.call),
              label: Text(
                _video
                    ? 'Rejoindre l\'appel vidéo'
                    : 'Rejoindre l\'appel audio',
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            TextButton.icon(
              onPressed: () => _copy(context, link),
              icon: const Icon(Icons.link, size: 18),
              label: const Text('Copier le lien'),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'L\'appel s\'ouvre dans Jitsi Meet (application ou navigateur). '
              'Autorisez ${_video ? 'la caméra et le micro' : 'le micro'} '
              'quand ils vous sont demandés ; en cas de refus, réactivez-les '
              'dans Réglages › Applications.'
              '${isDoctor ? ' Médecin : sur meet.jit.si, connectez-vous une '
                        'fois (Google ou GitHub) pour ouvrir la salle.' : ''}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
