import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/foodsave_api.dart';

/// Shared FoodSave UI kit. Palette (WCAG 2.1 AA checked):
/// - [AppColors.moduleFoodSave] #E07B1F: fills, icons, charts, tints.
///   Text on it must be [AppColors.text] (4.9:1), never white (3.0:1).
/// - [AppColors.moduleFoodSaveDeep] #A3520D: white-text CTAs (5.6:1) and
///   FoodSave-coloured text on white.
/// - [AppColors.accent] #FF8A3D: one key action / highlight, dark text.
/// - [AppColors.warning] #F2B84B: expiring soon, dark text.
class FoodSaveMotion {
  const FoodSaveMotion._();
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 280);
  static const Curve curve = Curves.easeOutCubic;
}

// --------------------------------------------------------------- chips

class _TintChip extends StatelessWidget {
  const _TintChip({
    required this.label,
    required this.color,
    this.icon,
    this.darkText = false,
  });

  final String label;
  final Color color;
  final IconData? icon;

  /// Required for accent / warning / moduleFoodSave (contrast rule).
  final bool darkText;

  @override
  Widget build(BuildContext context) {
    final fg = darkText ? AppColors.text : color;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: darkText ? 0.22 : 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

class BasketStatusChip extends StatelessWidget {
  const BasketStatusChip(this.status, {super.key});

  final BasketStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
        BasketStatus.disponible => _TintChip(
            label: status.label,
            color: AppColors.success,
            icon: Icons.check_circle_outline),
        BasketStatus.epuise => _TintChip(
            label: status.label,
            color: AppColors.warning,
            icon: Icons.inventory_2_outlined,
            darkText: true),
        BasketStatus.expire => _TintChip(
            label: status.label,
            color: AppColors.textSecondaryStrong,
            icon: Icons.schedule),
        BasketStatus.annule => _TintChip(
            label: status.label,
            color: AppColors.error,
            icon: Icons.block),
      };
}

class ReservationStatusChip extends StatelessWidget {
  const ReservationStatusChip(this.status, {super.key});

  final ReservationStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
        ReservationStatus.enAttente => _TintChip(
            label: status.label,
            color: AppColors.info,
            icon: Icons.qr_code_2),
        ReservationStatus.retire => _TintChip(
            label: status.label,
            color: AppColors.success,
            icon: Icons.check_circle_outline),
        ReservationStatus.expire => _TintChip(
            label: status.label,
            color: AppColors.warning,
            icon: Icons.timer_off_outlined,
            darkText: true),
        ReservationStatus.annule => _TintChip(
            label: status.label,
            color: AppColors.error,
            icon: Icons.block),
      };
}

/// True for a cash reservation: the client settles it with the merchant at
/// pickup, even though the FoodSave transaction is recorded as `paye`.
bool isCashReservation(ReservationDto r) =>
    r.modePaiement == PaymentMethodType.especes;

/// Payment status of a reservation. Cash is paid at pickup, so a cash
/// reservation never reads "Payé" before the pickup: it shows [cashLabel]
/// ("Confirmée" in lists, "Paiement au retrait" on the QR screen...).
class ReservationPaymentChip extends StatelessWidget {
  const ReservationPaymentChip(this.reservation,
      {super.key, this.cashLabel = 'Confirmée'});

  final ReservationDto reservation;
  final String cashLabel;

  @override
  Widget build(BuildContext context) {
    final r = reservation;
    final settled = r.statutPaiement == TransactionStatus.paye ||
        r.statutPaiement == TransactionStatus.rembourse;
    if (!isCashReservation(r) || !settled) return StatusChip(r.statutPaiement);
    return switch (r.statut) {
      ReservationStatus.enAttente => _TintChip(
          label: cashLabel,
          color: AppColors.success,
          icon: Icons.payments_outlined),
      ReservationStatus.retire => const StatusChip(TransactionStatus.paye),
      ReservationStatus.expire || ReservationStatus.annule => const _TintChip(
          label: 'Aucun paiement',
          color: AppColors.textSecondaryStrong,
          icon: Icons.money_off_outlined),
    };
  }
}

/// "-67 %" badge on the accent colour (dark text, contrast 6.3:1).
class DiscountBadge extends StatelessWidget {
  const DiscountBadge({
    super.key,
    required this.prixCentimes,
    required this.prixInitialCentimes,
    this.large = false,
  });

  final int prixCentimes;
  final int prixInitialCentimes;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final pct = FoodSaveRules.discountPercent(prixCentimes, prixInitialCentimes);
    if (pct <= 0) return const SizedBox.shrink();
    return Semantics(
      label: 'Réduction de $pct pour cent',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: large ? AppSpacing.sm : AppSpacing.xs,
            vertical: large ? 6 : 3),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text('-$pct %',
            style: TextStyle(
                fontSize: large ? 14 : 12,
                fontWeight: FontWeight.w800,
                color: AppColors.text)),
      ),
    );
  }
}

/// "1,2 km" pill. Null distance renders nothing.
class DistancePill extends StatelessWidget {
  const DistancePill(this.distanceKm, {super.key});

  final double? distanceKm;

  static String format(double km) => km < 1
      ? '${(km * 1000).round()} m'
      : '${km.toStringAsFixed(1).replaceAll('.', ',')} km';

  @override
  Widget build(BuildContext context) {
    final d = distanceKm;
    if (d == null) return const SizedBox.shrink();
    return _TintChip(
        label: format(d), color: AppColors.info, icon: Icons.near_me_outlined);
  }
}

// ------------------------------------------------------------- category

class FoodCategoryMeta {
  const FoodCategoryMeta._();

  static IconData icon(FoodCategory c) => switch (c) {
        FoodCategory.boulangerie => Icons.bakery_dining_outlined,
        FoodCategory.fruitsLegumes => Icons.eco_outlined,
        FoodCategory.platsPrepares => Icons.ramen_dining_outlined,
        FoodCategory.epicerie => Icons.local_grocery_store_outlined,
        FoodCategory.produitsLaitiers => Icons.egg_alt_outlined,
        FoodCategory.patisserie => Icons.cake_outlined,
        FoodCategory.mixte => Icons.shopping_basket_outlined,
      };
}

// ---------------------------------------------------------------- image

/// Basket photo (authenticated) with a tinted category placeholder; fades in.
class BasketImage extends StatelessWidget {
  const BasketImage({
    super.key,
    required this.api,
    required this.basket,
    this.height = 160,
    this.borderRadius = AppRadius.lg,
  });

  final FoodSaveApi api;
  final BasketDto basket;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      height: height,
      color: AppColors.moduleFoodSaveSoft,
      alignment: Alignment.center,
      child: Icon(FoodCategoryMeta.icon(basket.categorie),
          size: height * 0.32, color: AppColors.moduleFoodSave),
    );
    final image = basket.image;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: image == null
            ? placeholder
            : Image.network(
                api.imageUrl(image),
                headers: api.imageHeaders,
                fit: BoxFit.cover,
                cacheHeight: (height * 3).round(),
                frameBuilder: (context, child, frame, sync) => sync
                    ? child
                    : AnimatedOpacity(
                        opacity: frame == null ? 0 : 1,
                        duration: FoodSaveMotion.medium,
                        curve: FoodSaveMotion.curve,
                        child: child,
                      ),
                errorBuilder: (context, error, stack) => placeholder,
              ),
      ),
    );
  }
}

// ------------------------------------------------------------ animation

/// Fade + slight upward slide on first build; [index] staggers list items
/// (capped so long lists stay fast).
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: FoodSaveMotion.medium);
  late final Animation<double> _a =
      CurvedAnimation(parent: _c, curve: FoodSaveMotion.curve);

  @override
  void initState() {
    super.initState();
    final delay = Duration(milliseconds: 40 * widget.index.clamp(0, 6));
    Future<void>.delayed(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return widget.child;
    }
    return FadeTransition(
      opacity: _a,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.06), end: Offset.zero)
            .animate(_a),
        child: widget.child,
      ),
    );
  }
}

/// Pulsing skeleton block for known layouts while loading.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.height = 16,
    this.width = double.infinity,
    this.radius = AppRadius.sm,
  });

  final double height;
  final double width;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.45, end: 1.0).animate(_c),
        child: Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            color: AppColors.outlineSoft,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      );
}

/// Skeleton list of basket cards (initial loads of known layouts).
class BasketListSkeleton extends StatelessWidget {
  const BasketListSkeleton({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) => ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.md),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (_, _) => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(height: 140, radius: AppRadius.lg),
            SizedBox(height: AppSpacing.sm),
            SkeletonBox(height: 18, width: 200),
            SizedBox(height: AppSpacing.xs),
            SkeletonBox(height: 14, width: 140),
          ],
        ),
      );
}

// --------------------------------------------------------------- errors

/// Friendly error with retry. Network errors get the offline wording.
class FoodSaveErrorView extends StatelessWidget {
  const FoodSaveErrorView({super.key, required this.error, this.onRetry});

  final Object? error;
  final VoidCallback? onRetry;

  static String messageOf(Object? error) {
    if (error is ApiException) {
      return error.isNetworkError
          ? 'Connexion impossible : vérifiez votre connexion Internet et que le serveur est lancé.'
          : error.message;
    }
    return 'Une erreur inattendue est survenue. Veuillez réessayer.';
  }

  @override
  Widget build(BuildContext context) {
    final offline = error is ApiException && (error as ApiException).isNetworkError;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(offline ? Icons.wifi_off_rounded : Icons.error_outline,
                  color: AppColors.error, size: 34),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(messageOf(error),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Floating SnackBar for action errors (French, corrective).
void showFoodSaveError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(FoodSaveErrorView.messageOf(error))));
}

/// Primary FoodSave CTA style (deep orange, white text — AA compliant).
ButtonStyle foodSaveFilledStyle() => FilledButton.styleFrom(
      backgroundColor: AppColors.moduleFoodSaveDeep,
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(52),
    );
