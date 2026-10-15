import 'dart:async';

import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/session/session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/money_text.dart';
import '../data/foodsave_api.dart';
import '../platform/foodsave_notification_poller.dart';
import '../platform/foodsave_notifications_screen.dart';
import '../widgets/foodsave_ui.dart';
import 'basket_form_screen.dart';
import 'charts/kpi_tile.dart';
import 'charts/status_donut_chart.dart';
import 'charts/weekly_bar_chart.dart';
import 'merchant_baskets_screen.dart';
import 'merchant_reservations_screen.dart';
import 'scan_screen.dart';
import 'store_setup_screen.dart';

/// Merchant home of FoodSave: greeting, store, quick actions, KPIs and the
/// activity charts (palette: FoodSave / accent for today / warning).
class MerchantDashboardScreen extends StatefulWidget {
  const MerchantDashboardScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<MerchantDashboardScreen> createState() =>
      _MerchantDashboardScreenState();
}

/// Everything the dashboard shows. [stats] is null while no store exists.
class _DashboardData {
  const _DashboardData({required this.store, required this.stats});

  final StoreDto? store;
  final MerchantStatsDto? stats;
}

class _MerchantDashboardScreenState extends State<MerchantDashboardScreen> {
  late final FoodSaveApi _api = FoodSaveApi(widget.session.api);
  late Future<_DashboardData> _future;

  /// Last successful load: kept on screen while refreshing.
  _DashboardData? _last;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DashboardData> _load() async {
    // Both requests in parallel; stats only matter once a store exists.
    final storeFuture = _api.getMyStore();
    final statsFuture = _api.merchantStats();
    StoreDto? store;
    try {
      store = await storeFuture;
    } catch (_) {
      statsFuture.ignore(); // no unhandled error from the parallel request
      rethrow;
    }
    final MerchantStatsDto? stats;
    if (store == null) {
      // No store yet: the onboarding card replaces the (empty) statistics.
      statsFuture.ignore();
      stats = null;
    } else {
      stats = await statsFuture;
    }
    final data = _DashboardData(store: store, stats: stats);
    _last = data;
    return data;
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    try {
      await future;
    } catch (e) {
      // Keep the previous content; explain the failure.
      if (mounted && _last != null) showFoodSaveError(context, e);
    }
  }

  Future<T?> _push<T>(Widget screen) => Navigator.of(context)
      .push<T>(MaterialPageRoute(builder: (_) => screen));

  Future<void> _openAndRefresh(Widget screen) async {
    await _push<Object?>(screen);
    if (mounted) unawaited(_refresh());
  }

  Future<void> _openStoreSetup(StoreDto? initial) async {
    final saved = await _push<StoreDto>(
        StoreSetupScreen(session: widget.session, initial: initial));
    if (!mounted || saved == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(initial == null
              ? 'Commerce « ${saved.nom} » configuré : vous pouvez publier vos paniers.'
              : 'Commerce mis à jour.')));
    unawaited(_refresh());
  }

  Future<void> _newBasket(StoreDto? store) async {
    if (store == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text(
                'Configurez d\'abord votre commerce pour publier un panier.')));
      return _openStoreSetup(null);
    }
    final created =
        await _push<BasketDto>(BasketFormScreen(session: widget.session));
    if (!mounted) return;
    if (created != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            SnackBar(content: Text('Panier « ${created.titre} » publié.')));
    }
    unawaited(_refresh());
  }

  Future<void> _openNotifications() async {
    await _push<Object?>(FoodSaveNotificationsScreen(session: widget.session));
    if (mounted) setState(() {}); // refresh the unread badge
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FoodSave'),
        actions: [
          _NotificationsButton(onPressed: _openNotifications),
          const SizedBox(width: AppSpacing.xxs),
        ],
      ),
      body: FutureBuilder<_DashboardData>(
        future: _future,
        builder: (context, snapshot) {
          final done = snapshot.connectionState == ConnectionState.done;
          final data = done && snapshot.hasData ? snapshot.data : _last;
          final Widget child;
          if (data != null) {
            child = _content(data);
          } else if (done && snapshot.hasError) {
            child = _error(snapshot.error);
          } else {
            child = const _DashboardSkeleton(key: ValueKey('skeleton'));
          }
          return AnimatedSwitcher(
            duration: FoodSaveMotion.medium,
            switchInCurve: FoodSaveMotion.curve,
            switchOutCurve: FoodSaveMotion.curve,
            child: child,
          );
        },
      ),
    );
  }

  Widget _error(Object? error) => RefreshIndicator(
        key: const ValueKey('error'),
        color: AppColors.moduleFoodSaveDeep,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: AppSpacing.xxl),
            FoodSaveErrorView(error: error, onRetry: _refresh),
          ],
        ),
      );

  Widget _content(_DashboardData data) {
    final store = data.store;
    final stats = data.stats;
    final prenom = widget.session.user?.prenom.trim() ?? '';
    final theme = Theme.of(context).textTheme;

    final sections = <Widget>[
      // Greeting + store.
      Text(prenom.isEmpty ? 'Bonjour' : 'Bonjour $prenom',
          style: theme.headlineMedium),
      const SizedBox(height: AppSpacing.xxs),
      if (store != null)
        _StoreLine(store: store, onEdit: () => _openStoreSetup(store))
      else
        Text('Réduisez le gaspillage et vendez vos invendus.',
            style: theme.bodyMedium),
      const SizedBox(height: AppSpacing.lg),
      if (store == null) ...[
        _OnboardingCard(onPressed: () => _openStoreSetup(null)),
        const SizedBox(height: AppSpacing.lg),
      ],
      FilledButton.icon(
        style: foodSaveFilledStyle(),
        onPressed: () => _newBasket(store),
        icon: const Icon(Icons.add_circle_outline),
        label: const Text('Nouveau panier'),
      ),
      const SizedBox(height: AppSpacing.sm),
      _QuickActions(
        onScan: () => _openAndRefresh(ScanScreen(session: widget.session)),
        onBaskets: () =>
            _openAndRefresh(MerchantBasketsScreen(session: widget.session)),
        onReservations: () => _openAndRefresh(
            MerchantReservationsScreen(session: widget.session)),
      ),
      if (stats != null) ...[
        const SizedBox(height: AppSpacing.xl),
        Text('Vos indicateurs', style: theme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        KpiGrid(children: [
          KpiTile(
            icon: Icons.shopping_basket_outlined,
            label: 'Paniers actifs',
            value: stats.paniersActifs,
          ),
          KpiTile(
            icon: Icons.qr_code_2,
            label: 'À retirer',
            value: stats.reservationsEnAttente,
            color: AppColors.accent,
            highlight: stats.reservationsEnAttente > 0,
          ),
          KpiTile(
            icon: Icons.eco_outlined,
            label: 'Repas sauvés',
            value: stats.repasSauves,
            color: AppColors.success,
          ),
          KpiTile(
            icon: Icons.payments_outlined,
            label: 'Revenus',
            value: stats.revenusCentimes,
            color: AppColors.moduleFoodSaveDeep,
            format: MoneyText.format,
          ),
        ]),
        const SizedBox(height: AppSpacing.lg),
        _WeeklyCard(days: stats.parJour),
        const SizedBox(height: AppSpacing.md),
        _ChartCard(
          title: 'Réservations par statut',
          subtitle: 'Depuis l\'ouverture de votre commerce',
          child: StatusDonutChart(
            parStatut: stats.parStatut,
            tauxRetrait: stats.tauxRetrait,
          ),
        ),
      ],
    ];

    return RefreshIndicator(
      key: const ValueKey('content'),
      color: AppColors.moduleFoodSaveDeep,
      onRefresh: _refresh,
      // A short, fixed set of sections: a non-recycling scroll view keeps
      // the charts (and their entrance animations) alive while scrolling.
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < sections.length; i++)
              sections[i] is SizedBox
                  ? sections[i]
                  : FadeSlideIn(index: i ~/ 2, child: sections[i]),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- widgets

class _NotificationsButton extends StatelessWidget {
  const _NotificationsButton({required this.onPressed});

  final VoidCallback onPressed;

  Widget _button(int unread) => IconButton(
        tooltip: unread == 0
            ? 'Notifications'
            : 'Notifications : $unread non lue${unread > 1 ? 's' : ''}',
        onPressed: onPressed,
        icon: Badge(
          isLabelVisible: unread > 0,
          label: Text(unread > 99 ? '99+' : '$unread'),
          child: const Icon(Icons.notifications_outlined),
        ),
      );

  @override
  Widget build(BuildContext context) {
    // Rebuilds live on every poll.
    return ValueListenableBuilder<int>(
      valueListenable: FoodSaveNotificationPoller.instance.unread,
      builder: (context, unread, _) => _button(unread),
    );
  }
}

class _StoreLine extends StatelessWidget {
  const _StoreLine({required this.store, required this.onEdit});

  final StoreDto store;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(FoodCategoryMeta.icon(store.categorie),
            size: 20, color: AppColors.moduleFoodSaveDeep),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${store.nom} · ${store.categorie.label}',
                style: theme.titleMedium
                    ?.copyWith(color: AppColors.moduleFoodSaveDeep),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                store.adresse,
                style: theme.bodySmall
                    ?.copyWith(color: AppColors.textSecondaryStrong),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Modifier le commerce',
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
        ),
      ],
    );
  }
}

class _OnboardingCard extends StatelessWidget {
  const _OnboardingCard({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.moduleFoodSaveSoft,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
            color: AppColors.moduleFoodSave.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.moduleFoodSave.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.storefront_outlined,
                    color: AppColors.moduleFoodSaveDeep),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('Configurez votre commerce',
                    style: theme.titleLarge),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Indiquez le nom, l\'adresse et la position de votre commerce : '
            'les clients proches seront prévenus dès que vous publiez un panier.',
            style: theme.bodyMedium?.copyWith(color: AppColors.text),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            style: foodSaveFilledStyle(),
            onPressed: onPressed,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Configurer mon commerce'),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onScan,
    required this.onBaskets,
    required this.onReservations,
  });

  final VoidCallback onScan;
  final VoidCallback onBaskets;
  final VoidCallback onReservations;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ActionTile(
              icon: Icons.qr_code_scanner,
              label: 'Scanner un QR',
              onTap: onScan,
              highlight: true,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _ActionTile(
                icon: Icons.inventory_2_outlined,
                label: 'Mes paniers',
                onTap: onBaskets),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _ActionTile(
                icon: Icons.receipt_long_outlined,
                label: 'Réservations',
                onTap: onReservations),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Accent tint (dark text) for the one key action.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final tint = highlight ? AppColors.accent : AppColors.moduleFoodSave;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: highlight ? tint.withValues(alpha: 0.14) : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(
              color: highlight
                  ? tint.withValues(alpha: 0.45)
                  : AppColors.outlineSoft),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 88),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon,
                      color: highlight
                          ? AppColors.text
                          : AppColors.moduleFoodSaveDeep),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontSize: 13, color: AppColors.text),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: theme.bodySmall),
            ],
            if (trailing != null) ...[
              const SizedBox(height: AppSpacing.sm),
              trailing!,
            ],
            const SizedBox(height: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

/// Weekly bars with the Réservations / Revenus toggle.
class _WeeklyCard extends StatefulWidget {
  const _WeeklyCard({required this.days});

  final List<DailyStatDto> days;

  @override
  State<_WeeklyCard> createState() => _WeeklyCardState();
}

class _WeeklyCardState extends State<_WeeklyCard> {
  WeeklyMetric _metric = WeeklyMetric.reservations;

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    final total = _metric == WeeklyMetric.reservations
        ? '${days.fold<int>(0, (a, d) => a + d.reservations)} réservations'
        : MoneyText.format(days.fold<int>(0, (a, d) => a + d.revenusCentimes));
    final theme = Theme.of(context).textTheme;
    return _ChartCard(
      title: 'Activité des 7 derniers jours',
      subtitle: _metric == WeeklyMetric.reservations
          ? 'Total : $total · aujourd\'hui en orange vif'
          : 'Total : $total · montants en DT',
      trailing: SegmentedButton<WeeklyMetric>(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: AppColors.moduleFoodSaveSoft,
          selectedForegroundColor: AppColors.moduleFoodSaveDeep,
        ),
        segments: const [
          ButtonSegment(
            value: WeeklyMetric.reservations,
            label: Text('Réservations'),
            icon: Icon(Icons.bar_chart),
          ),
          ButtonSegment(
            value: WeeklyMetric.revenus,
            label: Text('Revenus'),
            icon: Icon(Icons.payments_outlined),
          ),
        ],
        selected: {_metric},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() => _metric = s.first),
      ),
      child: days.every((d) => d.reservations == 0)
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WeeklyBarChart(days: days, metric: _metric, height: 180),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Aucune réservation cette semaine : publiez un panier pour '
                  'attirer les clients proches.',
                  style: theme.bodySmall,
                ),
              ],
            )
          : WeeklyBarChart(days: days, metric: _metric),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Chargement du tableau de bord',
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          SkeletonBox(height: 28, width: 180),
          SizedBox(height: AppSpacing.xs),
          SkeletonBox(height: 18, width: 220),
          SizedBox(height: AppSpacing.lg),
          SkeletonBox(height: 52, radius: AppRadius.md),
          SizedBox(height: AppSpacing.sm),
          Row(children: [
            Expanded(child: SkeletonBox(height: 88, radius: AppRadius.md)),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: SkeletonBox(height: 88, radius: AppRadius.md)),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: SkeletonBox(height: 88, radius: AppRadius.md)),
          ]),
          SizedBox(height: AppSpacing.xl),
          Row(children: [
            Expanded(child: SkeletonBox(height: 112, radius: AppRadius.lg)),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: SkeletonBox(height: 112, radius: AppRadius.lg)),
          ]),
          SizedBox(height: AppSpacing.sm),
          Row(children: [
            Expanded(child: SkeletonBox(height: 112, radius: AppRadius.lg)),
            SizedBox(width: AppSpacing.sm),
            Expanded(child: SkeletonBox(height: 112, radius: AppRadius.lg)),
          ]),
          SizedBox(height: AppSpacing.lg),
          SkeletonBox(height: 280, radius: AppRadius.lg),
        ],
      ),
    );
  }
}
