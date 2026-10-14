import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/teledoc_repository.dart';

/// Symptom photo of a request, loaded through the authenticated endpoint.
/// Tapping it opens a zoomable full-screen view.
class TeledocRequestPhoto extends StatelessWidget {
  const TeledocRequestPhoto({
    super.key,
    required this.repository,
    required this.request,
    this.height = 180,
  });

  final TeledocRepository repository;
  final TeledocRequestDto request;
  final double height;

  @override
  Widget build(BuildContext context) {
    final source = repository.photoOf(request);
    final image = Image.network(
      source.url,
      headers: source.headers,
      fit: BoxFit.cover,
      semanticLabel: 'Photo du symptôme',
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : const Center(child: CircularProgressIndicator()),
      errorBuilder: (context, error, stack) => const _PhotoPlaceholder(
        icon: Icons.broken_image_outlined,
        label: 'Photo indisponible',
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Material(
          color: AppColors.outlineSoft,
          child: InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  backgroundColor: Colors.black,
                  appBar: AppBar(foregroundColor: Colors.white),
                  body: Center(
                    child: InteractiveViewer(
                      child: Image.network(source.url, headers: source.headers),
                    ),
                  ),
                ),
              ),
            ),
            child: image,
          ),
        ),
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.textSecondary),
        const SizedBox(height: AppSpacing.xxs),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}
