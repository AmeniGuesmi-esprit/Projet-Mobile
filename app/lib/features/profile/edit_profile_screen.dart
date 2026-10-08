import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/api/api_client.dart';
import '../../core/session/session_controller.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/primary_button.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nomController;
  late final TextEditingController _prenomController;
  late final TextEditingController _telephoneController;
  late final TextEditingController _ribController;

  bool _loading = false;
  String? _error;

  bool get _ribEditable => widget.session.user?.role.requiresRib ?? false;

  @override
  void initState() {
    super.initState();
    final user = widget.session.user;
    _nomController = TextEditingController(text: user?.nom ?? '');
    _prenomController = TextEditingController(text: user?.prenom ?? '');
    _telephoneController =
        TextEditingController(text: user?.telephone ?? '');
    _ribController = TextEditingController();
  }

  @override
  void dispose() {
    _nomController.dispose();
    _prenomController.dispose();
    _telephoneController.dispose();
    _ribController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final fields = <String, dynamic>{
        'nom': _nomController.text.trim(),
        'prenom': _prenomController.text.trim(),
        'telephone': _telephoneController.text.trim(),
      };
      final rib = _ribController.text.trim();
      if (_ribEditable && rib.isNotEmpty) fields['rib'] = rib;
      await widget.session.updateProfile(fields);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil mis à jour')),
      );
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Une erreur est survenue, veuillez réessayer');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Modifier mon profil')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          keyboardDismissBehavior:
              ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            if (_error != null) ...[
              Text(
                _error!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            Form(
              key: _formKey,
              autovalidateMode:
                  AutovalidateMode.onUserInteraction,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _prenomController,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration:
                        const InputDecoration(labelText: 'Prénom'),
                    validator: (v) => (v == null || !isValidName(v))
                        ? 'Prénom invalide'
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _nomController,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Nom'),
                    validator: (v) => (v == null || !isValidName(v))
                        ? 'Nom invalide'
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _telephoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Téléphone',
                      helperText: 'France (06…) ou Tunisie (+216…)',
                    ),
                    validator: (v) => (v == null || !isValidPhone(v))
                        ? 'Numéro invalide (France ou Tunisie)'
                        : null,
                  ),
                  if (_ribEditable) ...[
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _ribController,
                      textCapitalization:
                          TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'Nouveau RIB',
                        helperText:
                            'Actuel : ${widget.session.user?.ribMasque ?? '-'}',
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return null;
                        return isValidRib(v)
                            ? null
                            : 'RIB invalide (vérifiez la clé)';
                      },
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  PrimaryButton(
                    label: 'Enregistrer',
                    isLoading: _loading,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
