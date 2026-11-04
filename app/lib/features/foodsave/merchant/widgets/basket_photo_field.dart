import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/foodsave_api.dart';
import '../../widgets/foodsave_ui.dart';

/// Max photo size accepted by the server.
const int maxBasketPhotoBytes = 2 * 1024 * 1024;

/// A photo chosen locally, ready for `uploadBasketImage`.
class PickedPhoto {
  const PickedPhoto(this.bytes, this.contentType);

  final Uint8List bytes;
  final String contentType;
}

/// "image/jpeg" / "image/png" from the magic bytes, else null.
String? detectImageContentType(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  return null;
}

/// Photo area of the basket form: preview + gallery / camera bottom sheet.
class BasketPhotoField extends StatelessWidget {
  const BasketPhotoField({
    super.key,
    required this.api,
    required this.picked,
    required this.onChanged,
    this.existing,
    this.enabled = true,
  });

  final FoodSaveApi api;

  /// The basket being edited (shows its current photo), if any.
  final BasketDto? existing;
  final PickedPhoto? picked;
  final ValueChanged<PickedPhoto?> onChanged;
  final bool enabled;

  Future<void> _choose(BuildContext context) async {
    final source = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            if (picked != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.error),
                title: const Text('Retirer la nouvelle photo'),
                onTap: () => Navigator.pop(sheetContext, 'remove'),
              ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ),
      ),
    );
    if (!context.mounted || source == null) return;
    if (source == 'remove') {
      onChanged(null);
      return;
    }
    try {
      final file = await ImagePicker().pickImage(
        source: source as ImageSource,
        maxWidth: 1280,
        imageQuality: 80,
      );
      if (file == null || !context.mounted) return;
      final bytes = await file.readAsBytes();
      if (!context.mounted) return;
      final type = detectImageContentType(bytes);
      if (type == null) {
        _snack(context,
            'Format non pris en charge : choisissez une photo JPEG ou PNG.');
        return;
      }
      if (bytes.length > maxBasketPhotoBytes) {
        _snack(context,
            'Photo trop lourde (2 Mo maximum) : choisissez une autre photo.');
        return;
      }
      onChanged(PickedPhoto(bytes, type));
    } on PlatformException catch (e) {
      developer.log('image picker failed', name: 'foodsave', error: e);
      if (context.mounted) {
        _snack(context,
            'Accès aux photos impossible : autorisez l\'appareil photo et la galerie dans les réglages.');
      }
    }
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    const height = 176.0;
    final Widget preview;
    if (picked != null) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Image.memory(
          picked!.bytes,
          height: height,
          width: double.infinity,
          fit: BoxFit.cover,
          cacheHeight: (height * 3).round(),
          gaplessPlayback: true,
        ),
      );
    } else if (existing?.image != null) {
      preview = BasketImage(api: api, basket: existing!, height: height);
    } else {
      preview = Container(
        height: height,
        decoration: BoxDecoration(
          color: AppColors.moduleFoodSaveSoft,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
              color: AppColors.moduleFoodSave.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_a_photo_outlined,
                size: 36, color: AppColors.moduleFoodSaveDeep),
            const SizedBox(height: AppSpacing.xs),
            Text('Ajouter une photo (recommandé)',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: AppColors.moduleFoodSaveDeep)),
            const SizedBox(height: AppSpacing.xxs),
            Text('JPEG ou PNG, 2 Mo maximum',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondaryStrong)),
          ],
        ),
      );
    }
    final hasPhoto = picked != null || existing?.image != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: hasPhoto ? 'Changer la photo du panier' : 'Ajouter une photo du panier',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? () => _choose(context) : null,
          child: Stack(
            children: [
              AnimatedSwitcher(
                duration: FoodSaveMotion.medium,
                switchInCurve: FoodSaveMotion.curve,
                child: KeyedSubtree(
                  key: ValueKey(picked?.bytes.hashCode ?? existing?.image),
                  child: preview,
                ),
              ),
              if (hasPhoto && enabled)
                Positioned(
                  right: AppSpacing.xs,
                  bottom: AppSpacing.xs,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(color: AppColors.outline),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_outlined,
                            size: 16, color: AppColors.moduleFoodSaveDeep),
                        SizedBox(width: AppSpacing.xxs),
                        Text('Changer',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.moduleFoodSaveDeep)),
                      ],
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
