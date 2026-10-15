import 'dart:async';

import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/session/session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../client/client_discovery_screen.dart';
import '../merchant/merchant_dashboard_screen.dart';
import '../widgets/foodsave_ui.dart';
import 'foodsave_notification_poller.dart';
import 'foodsave_platform_hooks.dart';
import 'location_service.dart';

/// FoodSave tab root: merchants get their dashboard, everyone else the
/// basket discovery. Shows a one-time card offering notifications (and
/// location for clients) — permissions are never requested at startup.
class FoodSaveHubScreen extends StatefulWidget {
  const FoodSaveHubScreen({super.key, required this.session});

  final SessionController session;

  /// Persistent flag: the permission card was handled (accepted or dismissed).
  static const String permissionPromptFlag = 'foodsave_permission_prompt_done';

  /// The client position is pushed at most once per app session from here
  /// (screens refresh it themselves afterwards).
  static bool _locationSyncedThisSession = false;

  /// Called on logout so the next user's position is pushed again.
  static void resetSessionState() => _locationSyncedThisSession = false;

  @override
  State<FoodSaveHubScreen> createState() => _FoodSaveHubScreenState();
}

class _FoodSaveHubScreenState extends State<FoodSaveHubScreen> {
  bool _showPrompt = false;
  bool _enabling = false;

  bool get _isMerchant => widget.session.user?.role == UserRole.commercant;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    final done =
        await FoodSavePlatformHooks.readFlag(FoodSaveHubScreen.permissionPromptFlag);
    if (!mounted) return;
    if (!done) setState(() => _showPrompt = true);
    if (!_isMerchant && !FoodSaveHubScreen._locationSyncedThisSession) {
      FoodSaveHubScreen._locationSyncedThisSession = true;
      // While the card is shown the user decides there; otherwise ask now.
      unawaited(FoodSaveLocationService.instance.refresh(
        FoodSaveNotificationPoller.instance.apiFactory(widget.session),
        askPermission: done,
      ));
    }
  }

  Future<void> _dismiss() async {
    setState(() => _showPrompt = false);
    await FoodSavePlatformHooks.writeFlag(
        FoodSaveHubScreen.permissionPromptFlag, true);
  }

  Future<void> _enable() async {
    setState(() => _enabling = true);
    var notificationsOk = false;
    try {
      notificationsOk =
          await FoodSavePlatformHooks.requestNotificationPermission();
    } catch (_) {
      notificationsOk = false;
    }
    LocationResult? location;
    if (!_isMerchant) {
      location = await FoodSaveLocationService.instance.refresh(
        FoodSaveNotificationPoller.instance.apiFactory(widget.session),
      );
    }
    if (!mounted) return;
    setState(() => _enabling = false);
    await _dismiss();
    if (!mounted) return;

    final issue = location?.issue;
    final String message;
    if (issue != null) {
      message = FoodSaveLocationService.messageFor(issue);
    } else if (!notificationsOk) {
      message =
          'Notifications refusées : vous pouvez les activer dans les paramètres du téléphone.';
    } else {
      message = _isMerchant
          ? 'Notifications activées : vous serez averti des réservations.'
          : 'C\'est prêt : vous serez averti des paniers près de chez vous.';
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        action: issue == null || issue == LocationIssue.unavailable
            ? null
            : SnackBarAction(
                label: 'Paramètres',
                onPressed: () =>
                    FoodSaveLocationService.instance.openSettings(issue),
              ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration = disableAnimations ? Duration.zero : FoodSaveMotion.medium;
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final merchant = _isMerchant;
        final content = AnimatedSwitcher(
          duration: duration,
          switchInCurve: FoodSaveMotion.curve,
          switchOutCurve: FoodSaveMotion.curve,
          child: merchant
              ? MerchantDashboardScreen(
                  key: const ValueKey('foodsave-merchant'),
                  session: widget.session)
              : ClientDiscoveryScreen(
                  key: const ValueKey('foodsave-client'),
                  session: widget.session),
        );
        // The one-time prompt floats at the bottom (non-blocking, slides in/out)
        // so it never pushes the screen's app bar or content down.
        return ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Stack(
            children: [
              Positioned.fill(child: content),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedSwitcher(
                  duration: duration,
                  switchInCurve: FoodSaveMotion.curve,
                  switchOutCurve: FoodSaveMotion.curve,
                  transitionBuilder: (child, animation) => SlideTransition(
                    position: Tween(
                            begin: const Offset(0, 1), end: Offset.zero)
                        .animate(animation),
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: _showPrompt
                      ? SafeArea(
                          key: const ValueKey('foodsave-prompt'),
                          top: false,
                          child: Material(
                            color: Colors.transparent,
                            elevation: 0,
                            child: _PermissionCard(
                              merchant: merchant,
                              busy: _enabling,
                              onEnable: _enable,
                              onDismiss: _dismiss,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.merchant,
    required this.busy,
    required this.onEnable,
    required this.onDismiss,
  });

  final bool merchant;
  final bool busy;
  final VoidCallback onEnable;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xs),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.moduleFoodSaveSoft,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
              color: AppColors.moduleFoodSave.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: AppColors.text.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.moduleFoodSave.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                      merchant
                          ? Icons.notifications_active_outlined
                          : Icons.near_me_outlined,
                      color: AppColors.moduleFoodSaveDeep,
                      size: 22),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        merchant
                            ? 'Ne manquez aucune réservation'
                            : 'Paniers anti-gaspillage près de chez vous',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        merchant
                            ? 'Activez les notifications pour être averti des réservations et des retraits.'
                            : 'Activez les notifications et la localisation pour être averti dès qu\'un panier est disponible à moins de 5 km.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppColors.textSecondaryStrong),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                TextButton(
                  onPressed: busy ? null : onDismiss,
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.moduleFoodSaveDeep,
                      minimumSize: const Size(48, 48)),
                  child: const Text('Plus tard'),
                ),
                FilledButton(
                  onPressed: busy ? null : onEnable,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.moduleFoodSaveDeep,
                    foregroundColor: AppColors.surface,
                    minimumSize: const Size(48, 48),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: AppColors.surface),
                        )
                      : const Text('Activer'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
