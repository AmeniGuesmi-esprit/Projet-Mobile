import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/session/session_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/money_text.dart';
import '../payment/new_payment_screen.dart';
import '../payment/payment_methods_screen.dart';
import '../service_now/service_now_hub_screen.dart';
import '../coach/presentation/widgets/coach_entry_card.dart';
import '../teledoc/presentation/widgets/teledoc_entry_card.dart';
import 'service_entry_card.dart';
import '../../core/live/live_refresh.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.session, this.onOpenTab});

  final SessionController session;

  /// Switches the bottom bar to a tab ('foodsave', 'covoiturage').
  final ValueChanged<String>? onOpenTab;

  /// Paiements, FoodSave then EcoRoute shortcuts (TeleDoc follows),
  /// worded per role.
  List<Widget> _serviceCards(UserRole? role) {
    final open = onOpenTab;
    if (role == null || open == null) return const [];
    final merchant = role == UserRole.commercant;
    final driver = role == UserRole.conducteur;
    return [
      ServiceEntryCard.custom(
        label: 'Paiements',
        badgeIcon: Icons.account_balance_wallet_outlined,
        color: AppColors.primary,
        icon: Icons.account_balance_wallet_outlined,
        title: 'Vos paiements',
        subtitle: 'Historique, reçus et remboursements',
        onTap: () => open('payments'),
      ),
      ServiceEntryCard(
        type: ServiceType.foodSave,
        icon: Icons.restaurant_outlined,
        title: merchant
            ? 'Gérer vos paniers anti-gaspi'
            : 'Paniers anti-gaspi près de vous',
        subtitle: merchant
            ? 'Publiez vos invendus, suivez les réservations'
            : 'Des invendus à petit prix chez vos commerçants',
        onTap: () => open('foodsave'),
      ),
      ServiceEntryCard(
        type: ServiceType.ecoRoute,
        icon: Icons.directions_car_outlined,
        title: driver ? 'Vos trajets en covoiturage' : 'Trouver un covoiturage',
        subtitle: driver
            ? 'Publiez un trajet, acceptez les passagers'
            : 'Partagez la route et les frais',
        onTap: () => open('covoiturage'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final user = session.user;
    return SafeArea(
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: session.refreshUser,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            const SizedBox(height: AppSpacing.xs),
            _Greeting(user: user),
            const SizedBox(height: AppSpacing.lg),
            _BalanceCard(session: session),
            const SizedBox(height: AppSpacing.xl),
            ..._serviceCards(user?.role),
            TeledocEntryCard(session: session),
            if (user != null)
              ServiceEntryCard(
                type: ServiceType.serviceNow,
                icon: Icons.build_outlined,
                title: user.role == UserRole.prestataire
                    ? 'Vos interventions à domicile'
                    : 'Un service à domicile',
                subtitle: user.role == UserRole.prestataire
                    ? 'Trouvez des demandes, suivez vos interventions'
                    : 'Plomberie, électricité, ménage et plus encore',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ServiceNowHubScreen(session: session),
                  ),
                ),
              ),
            CoachEntryCard(session: session),
          ],
        ),
      ),
    );
  }
}

/// Initials avatar, « Bonjour » + first name, and a question.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.user});

  final UserDto? user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = user?.prenom ?? '';
    final initials = [
      first,
      user?.nom ?? '',
    ].where((s) => s.isNotEmpty).map((s) => s[0].toUpperCase()).join();
    return Row(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: const Color(0xFFD9F5E8),
          child: Text(
            initials.isEmpty ? '?' : initials,
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bonjour $first 👋',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: const Color(0xFF1B2559),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                "Que voulez-vous faire aujourd'hui ?",
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF2F6F5E),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Green balance card: wallet label, amount, « Portefeuille ProxiLife »
/// with a shield, a wallet illustration, and the Payer / Mes moyens
/// buttons inside the card.
class _BalanceCard extends StatefulWidget {
  const _BalanceCard({required this.session});

  final SessionController session;

  @override
  State<_BalanceCard> createState() => _BalanceCardState();
}

class _BalanceCardState extends State<_BalanceCard>
    with LiveRefresh<_BalanceCard> {
  static const Color _ink = Color(0xFF0F5E40); // dark green on mint

  SessionController get session => widget.session;

  /// Keeps the balance up to date (payments received, refunds...).
  @override
  Future<void> liveRefresh() => session.refreshUser();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = session.user;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A9A6B), Color(0xFF0E7550)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg + 4),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 18,
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          'Solde disponible',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: MoneyText(
                        user?.soldeCentimes ?? 0,
                        style: theme.textTheme.displaySmall?.copyWith(
                          color: Colors.white,
                          fontSize: 36,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user?.role.requiresRib == true
                                ? 'Revenus versés sur votre RIB'
                                : 'Portefeuille ProxiLife',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.verified_user_rounded,
                          color: Color(0xFFB4F2D6),
                          size: 18,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const _WalletArt(),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _CardButton(
                  icon: Icons.qr_code_scanner_rounded,
                  label: 'Payer',
                  background: Colors.white,
                  foreground: AppColors.primary,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<bool>(
                        builder: (_) => NewPaymentScreen(session: session),
                      ),
                    );
                    await session.refreshUser();
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _CardButton(
                  icon: Icons.credit_card_rounded,
                  label: 'Mes moyens',
                  background: const Color(0xFFD4F2E4),
                  foreground: _ink,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<PaymentMethodsScreen>(
                        builder: (_) => PaymentMethodsScreen(api: session.api),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pill button on the balance card.
class _CardButton extends StatelessWidget {
  const _CardButton({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: foreground, size: 20),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mint wallet with two cards sticking out and a few yellow sparkles.
class _WalletArt extends StatelessWidget {
  const _WalletArt();

  @override
  Widget build(BuildContext context) {
    Widget card(Color color, double angle) => Transform.rotate(
      angle: angle,
      child: Container(
        width: 44,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
    return ExcludeSemantics(
      child: SizedBox(
        width: 100,
        height: 88,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 14,
              top: 12,
              child: card(const Color(0xFFFFC94D), -0.3),
            ),
            Positioned(
              left: 32,
              top: 8,
              child: card(const Color(0xFF8E7BFF), 0.12),
            ),
            Positioned(
              left: 4,
              top: 28,
              child: Container(
                width: 80,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7FEBC4), Color(0xFF2CBB89)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
              ),
            ),
            // Clasp.
            Positioned(
              left: 62,
              top: 44,
              child: Container(
                width: 28,
                height: 24,
                decoration: BoxDecoration(
                  color: const Color(0xFF169A6C),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFFB4F2D6),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
            const Positioned(
              right: 0,
              top: 0,
              child: SizedBox(
                width: 24,
                height: 24,
                child: CustomPaint(painter: _SparkPainter()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFFFFD54F)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final w = size.width;
    final h = size.height;
    canvas.drawLine(Offset(w * 0.15, h * 0.05), Offset(w * 0.3, h * 0.4), p);
    canvas.drawLine(Offset(w * 0.6, h * 0.25), Offset(w * 0.95, h * 0.1), p);
    canvas.drawLine(Offset(w * 0.55, h * 0.6), Offset(w * 0.95, h * 0.65), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
