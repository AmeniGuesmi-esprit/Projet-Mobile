import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Visual identity of a ProxiLife service module (tint pill with icon+label).
class ServiceMeta {
  const ServiceMeta._();

  static const Map<ServiceType, ({String label, Color color, IconData icon})> _meta = {
    ServiceType.ecoRoute: (
      label: 'EcoRoute',
      color: AppColors.moduleEcoRoute,
      icon: Icons.directions_car_filled_outlined,
    ),
    ServiceType.foodSave: (
      label: 'FoodSave',
      color: AppColors.moduleFoodSave,
      icon: Icons.restaurant_outlined,
    ),
    ServiceType.teleDoc: (
      label: 'TeleDoc Express',
      color: AppColors.moduleTeleDoc,
      icon: Icons.medical_services_outlined,
    ),
    ServiceType.coachProche: (
      label: 'CoachProche',
      color: AppColors.moduleCoachProche,
      icon: Icons.fitness_center_outlined,
    ),
    ServiceType.serviceNow: (
      label: 'ServiceNow',
      color: AppColors.moduleCompte,
      icon: Icons.build_outlined,
    ),
  };

  static ({String label, Color color, IconData icon}) of(ServiceType type) =>
      _meta[type]!;
}

class ServiceBadge extends StatelessWidget {
  const ServiceBadge(this.type, {super.key, this.compact = false});

  final ServiceType type;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final meta = ServiceMeta.of(type);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.xs : AppSpacing.sm,
        vertical: compact ? 4 : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: meta.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: meta.color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(meta.icon, size: 14, color: meta.color),
          const SizedBox(width: 6),
          Text(
            meta.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: meta.color,
            ),
          ),
        ],
      ),
    );
  }
}
