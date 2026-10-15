import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../../core/session/session_controller.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/money_text.dart';
import '../../widgets/teledoc_submit_button.dart';
import '../../../domain/teledoc_repository.dart';
import '../../widgets/teledoc_async_view.dart';
import '../../widgets/teledoc_photo.dart';

/// Picks a photo from the camera or the gallery; `null` if cancelled.
typedef TeledocImagePicker = Future<Uint8List?> Function(ImageSource source);

/// Default picker: resized and recompressed on the device so that most
/// photos stay far below the 2 MB server limit.
Future<Uint8List?> pickTeledocImage(ImageSource source) async {
  final picked = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 80,
  );
  return picked?.readAsBytes();
}

/// Creates a request (with optional photo, payment included) or edits a
/// waiting one ([initial] set). Pops with the saved request.
class TeledocRequestFormScreen extends StatefulWidget {
  const TeledocRequestFormScreen({
    super.key,
    required this.session,
    required this.repository,
    this.initial,
    this.pickImage = pickTeledocImage,
  });

  final SessionController session;
  final TeledocRepository repository;
  final TeledocRequestDto? initial;
  final TeledocImagePicker pickImage;

  @override
  State<TeledocRequestFormScreen> createState() =>
      _TeledocRequestFormScreenState();
}

class _TeledocRequestFormScreenState extends State<TeledocRequestFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _motif = TextEditingController(
    text: widget.initial?.motif,
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.initial?.description,
  );
  late TeledocUrgency _urgency =
      widget.initial?.urgence ?? TeledocUrgency.moyenne;

  /// Newly picked photo (not sent yet).
  Uint8List? _photo;

  /// Edit mode: the user asked to remove the existing photo.
  bool _removeExisting = false;
  bool _submitting = false;

  bool get _isEdit => widget.initial != null;
  bool get _hasExistingPhoto =>
      (widget.initial?.aPhoto ?? false) && !_removeExisting && _photo == null;

  @override
  void dispose() {
    _motif.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _choosePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.photo_camera_outlined,
                color: AppColors.primary,
              ),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: AppColors.primary,
              ),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final bytes = await widget.pickImage(source);
      if (bytes == null || !mounted) return;
      // UX-only pre-check; the server re-validates size and real file type.
      if (bytes.length > TeledocPhotoRules.maxBytes) {
        showTeledocSnack(context, 'Photo trop volumineuse : 2 Mo maximum');
        return;
      }
      setState(() {
        _photo = bytes;
        _removeExisting = false;
      });
    } catch (_) {
      if (mounted) {
        showTeledocSnack(
          context,
          'Impossible d\'accéder à l\'appareil photo ou à la galerie. '
          'Vérifiez les autorisations.',
        );
      }
    }
  }

  void _removePhoto() => setState(() {
    _photo = null;
    _removeExisting = _isEdit && (widget.initial?.aPhoto ?? false);
  });

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    try {
      final initial = widget.initial;
      final TeledocRequestDto saved;
      if (initial == null) {
        saved = await widget.repository.createRequest(
          motif: _motif.text.trim(),
          description: _description.text.trim(),
          urgence: _urgency,
          photoBytes: _photo,
        );
      } else {
        String? changed(String value, String old) =>
            value.trim() == old ? null : value.trim();
        final motif = changed(_motif.text, initial.motif);
        final description = changed(_description.text, initial.description);
        final urgence = _urgency == initial.urgence ? null : _urgency;
        if (motif == null &&
            description == null &&
            urgence == null &&
            _photo == null &&
            !_removeExisting) {
          // Nothing to send: the server would answer « Aucune modification ».
          Navigator.of(context).pop(initial);
          return;
        }
        saved = await widget.repository.updateRequest(
          initial.id,
          motif: motif,
          description: description,
          urgence: urgence,
          photoBytes: _photo,
          removePhoto: _removeExisting,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      // Keep the user's input (flutter-ux-patterns: never clear on error).
      setState(() => _submitting = false);
      showTeledocSnack(
        context,
        teledocErrorMessage(e),
        actionLabel: 'Réessayer',
        onAction: _submit,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = widget.initial;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Modifier la demande' : 'Nouvelle demande'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          // Not a lazy ListView: Form.validate() only checks mounted fields,
          // so every field must stay built even when scrolled off-screen.
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _motif,
                  decoration: const InputDecoration(
                    labelText: 'Motif',
                    hintText: 'Ex. : fièvre, toux, douleur…',
                  ),
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 80,
                  validator: teledocMotifError,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextFormField(
                  controller: _description,
                  decoration: const InputDecoration(
                    labelText: 'Description des symptômes',
                    hintText:
                        'Depuis quand ? Quelle intensité ? Traitements '
                        'déjà pris ?',
                    alignLabelWithHint: true,
                  ),
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: 1000,
                  validator: teledocDescriptionError,
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Urgence', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                SegmentedButton<TeledocUrgency>(
                  segments: [
                    for (final u in TeledocUrgency.values)
                      ButtonSegment(value: u, label: Text(u.label)),
                  ],
                  selected: {_urgency},
                  onSelectionChanged: (s) => setState(() => _urgency = s.first),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Les demandes urgentes passent en priorité. En cas d\'urgence '
                  'vitale, appelez le 190 (SAMU).',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Photo du symptôme (facultatif)',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                if (_photo != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Image.memory(
                      _photo!,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      semanticLabel: 'Photo sélectionnée',
                    ),
                  )
                else if (_hasExistingPhoto && initial != null)
                  TeledocRequestPhoto(
                    repository: widget.repository,
                    request: initial,
                  ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _submitting ? null : _choosePhoto,
                        icon: const Icon(Icons.add_a_photo_outlined),
                        label: Text(
                          _photo != null || _hasExistingPhoto
                              ? 'Changer'
                              : 'Ajouter une photo',
                        ),
                      ),
                    ),
                    if (_photo != null || _hasExistingPhoto) ...[
                      const SizedBox(width: AppSpacing.xs),
                      IconButton(
                        tooltip: 'Retirer la photo',
                        onPressed: _submitting ? null : _removePhoto,
                        icon: const Icon(
                          Icons.delete_outline,
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                if (!_isEdit)
                  Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.account_balance_wallet_outlined,
                        color: AppColors.primary,
                      ),
                      title: const Text('Tarif de la téléconsultation'),
                      subtitle: const Text(
                        'Débité à l\'envoi, remboursé si vous annulez avant '
                        'la consultation.',
                      ),
                      trailing: Text(
                        MoneyText.format(TeledocPricing.consultationCents),
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
                TeledocSubmitButton(
                  label: _isEdit
                      ? 'Enregistrer'
                      : 'Payer et envoyer la demande',
                  icon: _isEdit ? Icons.check : Icons.send,
                  isLoading: _submitting,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
