import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/api/api_client.dart';
import '../../core/session/session_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/primary_button.dart';
import 'verify_screen.dart';

/// Role choices presented to the user (admin is never self-assignable).
const _selectableRoles = <UserRole, String>{
  UserRole.client: 'Client',
  UserRole.conducteur: 'Conducteur',
  UserRole.commercant: 'Commerçant',
  UserRole.medecin: 'Médecin',
  UserRole.coach: 'Coach',
};

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomController = TextEditingController();
  final _prenomController = TextEditingController();
  final _emailController = TextEditingController();
  final _telephoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _ribController = TextEditingController();

  UserRole _role = UserRole.client;
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _nomController.dispose();
    _prenomController.dispose();
    _emailController.dispose();
    _telephoneController.dispose();
    _passwordController.dispose();
    _ribController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final email = _emailController.text.trim();
    try {
      await widget.session.register(
        nom: _nomController.text.trim(),
        prenom: _prenomController.text.trim(),
        email: email,
        telephone: _telephoneController.text.trim(),
        motDePasse: _passwordController.text,
        role: _role,
        rib: _ribController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<VerifyScreen>(
          builder: (_) =>
              VerifyScreen(session: widget.session, email: email),
        ),
      );
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
      appBar: AppBar(title: const Text('Créer un compte')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.35)),
                ),
                child: Text(
                  _error!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.error),
                ),
              ),
            ],
            Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AutofillGroup(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _prenomController,
                                textCapitalization:
                                    TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                autofillHints: const [AutofillHints.givenName],
                                decoration: const InputDecoration(
                                    labelText: 'Prénom'),
                                validator: (v) =>
                                    (v == null || !isValidName(v))
                                        ? 'Prénom invalide'
                                        : null,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: TextFormField(
                                controller: _nomController,
                                textCapitalization:
                                    TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                autofillHints:
                                    const [AutofillHints.familyName],
                                decoration:
                                    const InputDecoration(labelText: 'Nom'),
                                validator: (v) =>
                                    (v == null || !isValidName(v))
                                        ? 'Nom invalide'
                                        : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'Adresse e-mail',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                          validator: (v) => (v == null || !isValidEmail(v))
                              ? 'Adresse e-mail invalide'
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _telephoneController,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          decoration: const InputDecoration(
                            labelText: 'Téléphone',
                            prefixIcon: Icon(Icons.phone_outlined),
                            helperText: 'France (06…) ou Tunisie (+216…)',
                          ),
                          validator: (v) => (v == null || !isValidPhone(v))
                              ? 'Numéro invalide (France ou Tunisie)'
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: InputDecoration(
                            labelText: 'Mot de passe',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? 'Afficher le mot de passe'
                                  : 'Masquer le mot de passe',
                              icon: Icon(_obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () => setState(() =>
                                  _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (v) => passwordPolicyError(v ?? ''),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '8 caractères minimum, 1 majuscule, 1 minuscule, 1 chiffre.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text('Votre rôle',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final entry in _selectableRoles.entries)
                        ChoiceChip(
                          label: Text(entry.value),
                          selected: _role == entry.key,
                          selectedColor:
                              AppColors.primary.withValues(alpha: 0.15),
                          labelStyle: TextStyle(
                            color: _role == entry.key
                                ? AppColors.primary
                                : AppColors.text,
                            fontWeight: _role == entry.key
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                          side: BorderSide(
                            color: _role == entry.key
                                ? AppColors.primary
                                : AppColors.outline,
                          ),
                          onSelected: (_) =>
                              setState(() => _role = entry.key),
                        ),
                    ],
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    child: _role.requiresRib
                        ? Padding(
                            padding:
                                const EdgeInsets.only(top: AppSpacing.lg),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.stretch,
                              children: [
                                TextFormField(
                                  controller: _ribController,
                                  keyboardType: TextInputType.text,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  maxLength: 27,
                                  decoration: const InputDecoration(
                                    labelText: 'RIB (requis)',
                                    prefixIcon:
                                        Icon(Icons.account_balance_outlined),
                                    counterText: '',
                                    helperText:
                                        'Pour percevoir vos revenus. 23 caractères.',
                                  ),
                                  validator: (v) =>
                                      (v == null || !isValidRib(v))
                                          ? 'RIB invalide (vérifiez la clé)'
                                          : null,
                                ),
                                Container(
                                  padding: const EdgeInsets.all(
                                      AppSpacing.sm),
                                  decoration: BoxDecoration(
                                    color: AppColors.info
                                        .withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(
                                        AppRadius.sm),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.info_outline,
                                          color: AppColors.info, size: 18),
                                      const SizedBox(width: AppSpacing.xs),
                                      Expanded(
                                        child: Text(
                                          'Les professionnels reçoivent leurs revenus sur ce RIB.',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  PrimaryButton(
                    label: 'Créer mon compte',
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
