import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/session/session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/money_text.dart';
import '../data/foodsave_api.dart';
import '../widgets/foodsave_ui.dart';
import 'basket_form_screen.dart';
import 'merchant_reservations_screen.dart';
import 'widgets/merchant_format.dart';
import 'widgets/merchant_reservation_tile.dart';

typedef _DetailData = ({BasketDto basket, List<ReservationDto> reservations});

/// One basket seen by its merchant: photo, KPIs, info, actions (edit /
/// cancel / delete) and its reservations.
class MerchantBasketDetailScreen extends StatefulWidget {
  const MerchantBasketDetailScreen(
      {super.key, required this.session, required this.basketId});

  final SessionController session;
  final int basketId;

  @override
  State<MerchantBasketDetailScreen> createState() =>
      _MerchantBasketDetailScreenState();
}

class _MerchantBasketDetailScreenState
    extends State<MerchantBasketDetailScreen> {
  static const int _previewCount = 5;

  late final FoodSaveApi _api = FoodSaveApi(widget.session.api);
  late Future<_DetailData> _future = _load();
  String? _pendingAction; // 'cancel' | 'delete'

  Future<_DetailData> _load() async {
    final results = await Future.wait<Object>([
      _api.getMyBasket(widget.basketId),
      _api.merchantReservations(panierId: widget.basketId),
    ]);
    return (
      basket: results[0] as BasketDto,
      reservations: results[1] as List<ReservationDto>,
    );
  }

  Future<void> _refresh() {
    final future = _load();
    setState(() => _future = future);
    return future.then((_) {}, onError: (_) {});
  }

  Future<void> _edit(BasketDto basket) async {
    final saved = await Navigator.of(context).push<BasketDto>(MaterialPageRoute(
        builder: (_) =>
            BasketFormScreen(session: widget.session, basket: basket)));
    if (saved != null && mounted) await _refresh();
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Retour'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 48),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _cancel(_DetailData data) async {
    final active = data.reservations
        .where((r) => FoodSaveRules.isReservationActive(r.statut))
        .length;
    final ok = await _confirm(
      title: 'Annuler ce panier ?',
      message: active == 0
          ? 'Le panier sera retiré de la vente. Cette action est définitive.'
          : 'Le panier sera retiré de la vente et ses $active réservation'
              '${active > 1 ? 's' : ''} en cours annulée${active > 1 ? 's' : ''}. '
              'Les clients concernés seront notifiés et les réservations payées '
              'remboursées lorsque c\'est possible. Cette action est définitive.',
      confirmLabel: 'Annuler le panier',
    );
    if (!ok || !mounted) return;
    setState(() => _pendingAction = 'cancel');
    try {
      await _api.cancelBasket(data.basket.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(active == 0
                ? 'Panier annulé'
                : 'Panier annulé · $active client${active > 1 ? 's' : ''} '
                    'notifié${active > 1 ? 's' : ''}')));
      await _refresh();
    } catch (e) {
      if (mounted) showFoodSaveError(context, e);
    } finally {
      if (mounted) setState(() => _pendingAction = null);
    }
  }

  Future<void> _delete(BasketDto basket) async {
    final ok = await _confirm(
      title: 'Supprimer définitivement ce panier ?',
      message:
          'Le panier « ${basket.titre} » sera supprimé. Cette action est irréversible.',
      confirmLabel: 'Supprimer',
    );
    if (!ok || !mounted) return;
    setState(() => _pendingAction = 'delete');
    try {
      await _api.deleteBasket(basket.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Panier supprimé')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _pendingAction = null);
      showFoodSaveError(context, e);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Détail du panier')),
      body: FutureBuilder<_DetailData>(
        future: _future,
        builder: (context, snapshot) {
          final Widget child;
          if (snapshot.hasData) {
            child = _content(snapshot.data!);
          } else if (snapshot.hasError) {
            child = FoodSaveErrorView(
                key: const ValueKey('error'),
                error: snapshot.error,
                onRetry: _refresh);
          } else {
            child = const _DetailSkeleton(key: ValueKey('loading'));
          }
          return AnimatedSwitcher(
            duration: FoodSaveMotion.medium,
            switchInCurve: FoodSaveMotion.curve,
            child: child,
          );
        },
      ),
    );
  }

  Widget _content(_DetailData data) {
    final theme = Theme.of(context);
    final b = data.basket;
    int sumWhere(ReservationStatus s) => data.reservations
        .where((r) => r.statut == s)
        .fold(0, (sum, r) => sum + r.quantiteReservee);
    final reserved = sumWhere(ReservationStatus.enAttente);
    final collected = sumWhere(ReservationStatus.retire);
    final editable = FoodSaveRules.isBasketEditable(b.statut);
    final busy = _pendingAction != null;

    return RefreshIndicator(
      key: const ValueKey('content'),
      onRefresh: _refresh,
      color: AppColors.moduleFoodSaveDeep,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xxl),
        children: [
          Stack(
            children: [
              Hero(
                tag: 'basket-image-${b.id}',
                child: BasketImage(api: _api, basket: b, height: 220),
              ),
              Positioned(
                left: AppSpacing.sm,
                top: AppSpacing.sm,
                child: DiscountBadge(
                    prixCentimes: b.prixCentimes,
                    prixInitialCentimes: b.prixInitialCentimes,
                    large: true),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: Text(b.titre, style: theme.textTheme.headlineSmall)),
              const SizedBox(width: AppSpacing.xs),
              BasketStatusChip(b.statut),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Wrap(
            spacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              MoneyText(b.prixCentimes,
                  style: theme.textTheme.titleLarge?.copyWith(
                      color: AppColors.moduleFoodSaveDeep,
                      fontWeight: FontWeight.w800)),
              MoneyText(b.prixInitialCentimes,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondaryStrong,
                      decoration: TextDecoration.lineThrough)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _Kpi(
                  icon: Icons.inventory_2_outlined,
                  value: '${b.quantite}',
                  caption: 'Unités restantes',
                  detail: 'sur ${b.quantiteInitiale}',
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _Kpi(
                    icon: Icons.qr_code_2,
                    value: '$reserved',
                    caption: 'Réservées'),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _Kpi(
                    icon: Icons.check_circle_outline,
                    value: '$collected',
                    caption: 'Retirées'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Column(
                children: [
                  _InfoRow(
                      icon: FoodCategoryMeta.icon(b.categorie),
                      label: 'Catégorie',
                      value: b.categorie.label),
                  _InfoRow(
                      icon: Icons.schedule,
                      label: 'Créneau de retrait',
                      value: formatPickupWindowFr(
                          b.creneauRetraitDebut, b.creneauRetraitFin)),
                  _InfoRow(
                      icon: Icons.event_busy_outlined,
                      label: 'Expiration',
                      value: formatDateTimeFr(b.dateExpiration)),
                  _InfoRow(
                      icon: Icons.campaign_outlined,
                      label: 'Publié',
                      value: formatDateTimeFr(b.creeLe)),
                  _InfoRow(
                      icon: Icons.notes_outlined,
                      label: 'Contenu',
                      value: b.contenu),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (editable) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.moduleFoodSaveDeep,
                      side: const BorderSide(
                          color: AppColors.moduleFoodSaveDeep, width: 1.4),
                    ),
                    onPressed: busy ? null : () => _edit(b),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Modifier'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error, width: 1.4),
                    ),
                    onPressed: busy ? null : () => _cancel(data),
                    icon: _pendingAction == 'cancel'
                        ? const _ButtonSpinner()
                        : const Icon(Icons.block),
                    label: const Text('Annuler le panier'),
                  ),
                ),
              ],
            ),
          ] else
            _TerminalNote(status: b.statut),
          if (data.reservations.isEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.error,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: busy ? null : () => _delete(b),
              icon: _pendingAction == 'delete'
                  ? const _ButtonSpinner()
                  : const Icon(Icons.delete_outline),
              label: const Text('Supprimer le panier'),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('Réservations · ${data.reservations.length}',
                      style: theme.textTheme.titleLarge),
                ),
              ),
              if (data.reservations.length > _previewCount)
                TextButton(
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.moduleFoodSaveDeep,
                      minimumSize: const Size(48, 48)),
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute<void>(
                          builder: (_) => MerchantReservationsScreen(
                              session: widget.session, basketId: b.id)))
                      .then((_) {
                    if (mounted) _refresh();
                  }),
                  child: const Text('Tout voir'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (data.reservations.isEmpty)
            Text(
              'Aucune réservation pour ce panier pour le moment.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textSecondaryStrong),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final (i, r)
                      in data.reservations.take(_previewCount).indexed) ...[
                    if (i > 0)
                      const Divider(
                          height: 1,
                          indent: AppSpacing.md,
                          endIndent: AppSpacing.md,
                          color: AppColors.outlineSoft),
                    MerchantReservationTile(
                        reservation: r, showBasketTitle: false),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
}

class _TerminalNote extends StatelessWidget {
  const _TerminalNote({required this.status});

  final BasketStatus status;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.outlineSoft,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_outline,
                size: 20, color: AppColors.textSecondaryStrong),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                status == BasketStatus.annule
                    ? 'Panier annulé : il n\'est plus modifiable.'
                    : 'Panier expiré : il n\'est plus modifiable.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.textSecondaryStrong),
              ),
            ),
          ],
        ),
      );
}

class _Kpi extends StatelessWidget {
  const _Kpi({
    required this.icon,
    required this.value,
    required this.caption,
    this.detail,
  });

  final IconData icon;
  final String value;
  final String caption;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$caption : $value${detail == null ? '' : ' $detail'}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.moduleFoodSaveSoft,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: AppColors.moduleFoodSaveDeep),
            const SizedBox(height: AppSpacing.xxs),
            Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: value,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                if (detail != null)
                  TextSpan(
                      text: ' $detail',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondaryStrong)),
              ]),
            ),
            Text(caption,
                maxLines: 2,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.textSecondaryStrong)),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: AppColors.moduleFoodSaveDeep),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondaryStrong)),
                  const SizedBox(height: 2),
                  Text(value, style: theme.textTheme.bodyLarge),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(height: 220, radius: AppRadius.lg),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(height: 24, width: 220),
            SizedBox(height: AppSpacing.xs),
            SkeletonBox(height: 18, width: 120),
            SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(child: SkeletonBox(height: 84, radius: AppRadius.md)),
                SizedBox(width: AppSpacing.xs),
                Expanded(child: SkeletonBox(height: 84, radius: AppRadius.md)),
                SizedBox(width: AppSpacing.xs),
                Expanded(child: SkeletonBox(height: 84, radius: AppRadius.md)),
              ],
            ),
          ],
        ),
      );
}
