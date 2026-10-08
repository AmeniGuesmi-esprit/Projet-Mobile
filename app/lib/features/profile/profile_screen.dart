import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/api/api_client.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/session/session_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import 'edit_profile_screen.dart';

const _roleLabels = <UserRole, String>{
  UserRole.client: 'Client',
  UserRole.conducteur: 'Conducteur',
  UserRole.commercant: 'Commerçant',
  UserRole.medecin: 'Médecin',
  UserRole.coach: 'Coach',
  UserRole.admin: 'Administrateur',
};

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _notificationsEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final enabled = await widget.session.settings.getNotificationsEnabled();
    if (mounted) setState(() => _notificationsEnabled = enabled);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _changePhoto() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.primary),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.pop(sheetContext, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppColors.primary),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(sheetContext, 'camera'),
            ),
            if (widget.session.user?.photo != null)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: AppColors.error),
                title: const Text('Supprimer la photo',
                    style: TextStyle(color: AppColors.error)),
                onTap: () => Navigator.pop(sheetContext, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    try {
      if (choice == 'remove') {
        await widget.session.updateProfile({'photo': null});
        return;
      }
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 70,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      await widget.session.updateProfile({'photo': base64Encode(bytes)});
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Impossible de mettre à jour la photo');
    }
  }

  Future<void> _toggleNotifications(bool value) async {
    if (value) {
      final granted =
          await NotificationService.instance.ensurePermission();
      if (!granted) {
        _showError('Activez les notifications dans les réglages Android');
        return;
      }
    }
    setState(() => _notificationsEnabled = value);
    await widget.session.settings.setNotificationsEnabled(value);
  }

  Future<void> _toggleBiometrics(bool value) async {
    if (value) {
      final localAuth = LocalAuthentication();
      try {
        final available = await localAuth.canCheckBiometrics ||
            await localAuth.isDeviceSupported();
        if (!available) {
          _showError(
              'Aucune biométrie disponible sur cet appareil');
          return;
        }
      } on LocalAuthException {
        _showError('Biométrie indisponible');
        return;
      }
    }
    await widget.session.setBiometricsEnabled(value);
  }

  Future<void> _deleteAccount() async {
    // First step: plain confirmation.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: AppColors.error, size: 40),
        title: const Text('Supprimer votre compte ?'),
        content: const Text(
          'Cette action est définitive : votre profil, vos moyens de paiement '
          'et vos sessions seront supprimés. Votre historique sera anonymisé.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Second step: typed confirmation + password.
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    String? error;
    final valid = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Confirmation définitive'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Tapez SUPPRIMER et saisissez votre mot de passe.'),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: confirmController,
                textCapitalization: TextCapitalization.characters,
                decoration:
                    const InputDecoration(labelText: 'Tapez SUPPRIMER'),
                onChanged: (_) => setDialogState(() {}),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: passwordController,
                obscureText: true,
                autocorrect: false,
                decoration:
                    const InputDecoration(labelText: 'Mot de passe'),
              ),
              if (error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(error!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.error)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
                minimumSize: const Size(0, 44),
              ),
              onPressed: confirmController.text.trim().toUpperCase() ==
                          'SUPPRIMER' &&
                      passwordController.text.isNotEmpty
                  ? () async {
                      try {
                        await widget.session
                            .deleteAccount(passwordController.text);
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } on ApiException catch (e) {
                        setDialogState(() => error = e.message);
                      } catch (_) {
                        setDialogState(() =>
                            error = 'Une erreur est survenue');
                      }
                    }
                  : null,
              child: const Text('Supprimer'),
            ),
          ],
        ),
      ),
    );
    if (valid == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Votre compte a été supprimé')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ListenableBuilder(
        listenable: widget.session,
        builder: (context, _) {
          final user = widget.session.user;
          if (user == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final roleLabel = _roleLabels[user.role] ?? user.role.apiValue;
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor:
                          AppColors.primary.withValues(alpha: 0.12),
                      backgroundImage: user.photo != null
                          ? MemoryImage(base64Decode(user.photo!))
                          : null,
                      child: user.photo == null
                          ? Text(
                              '${user.prenom.characters.first}${user.nom.characters.first}'
                                  .toUpperCase(),
                              style: theme.textTheme.headlineMedium
                                  ?.copyWith(color: AppColors.primary),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Material(
                        color: AppColors.primary,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _changePhoto,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.edit,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: Text(user.nomComplet,
                    style: theme.textTheme.titleLarge),
              ),
              Center(
                child: Text(user.email, style: theme.textTheme.bodyMedium),
              ),
              const SizedBox(height: AppSpacing.xs),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    roleLabel,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: AppColors.primary, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _Section(
                title: 'Informations',
                children: [
                  _InfoTile(
                    icon: Icons.phone_outlined,
                    label: 'Téléphone',
                    value: user.telephone,
                  ),
                  if (user.ribMasque != null)
                    _InfoTile(
                      icon: Icons.account_balance_outlined,
                      label: 'RIB',
                      value: user.ribMasque!,
                    ),
                  _ActionTile(
                    icon: Icons.edit_outlined,
                    label: 'Modifier mon profil',
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<EditProfileScreen>(
                          builder: (_) =>
                              EditProfileScreen(session: widget.session),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Section(
                title: 'Sécurité & notifications',
                children: [
                  SwitchListTile(
                    secondary:
                        const Icon(Icons.fingerprint, color: AppColors.primary),
                    title: const Text('Connexion biométrique'),
                    subtitle: const Text(
                        'Face ID / empreinte au démarrage de l\'app'),
                    value: widget.session.biometricsEnabled,
                    onChanged: _toggleBiometrics,
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.notifications_outlined,
                        color: AppColors.primary),
                    title: const Text('Notifications'),
                    subtitle: const Text(
                        'Vérification, paiements et remboursements'),
                    value: _notificationsEnabled,
                    onChanged: _toggleNotifications,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _Section(
                title: 'Compte',
                children: [
                  _ActionTile(
                    icon: Icons.logout,
                    label: 'Se déconnecter',
                    onTap: widget.session.logout,
                  ),
                  _ActionTile(
                    icon: Icons.delete_forever_outlined,
                    label: 'Supprimer mon compte',
                    color: AppColors.error,
                    onTap: _deleteAccount,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
              left: AppSpacing.xs, bottom: AppSpacing.xs),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        Card(
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary),
      title: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      subtitle: Text(value, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effective = color ?? AppColors.text;
    return ListTile(
      leading: Icon(icon, color: color ?? AppColors.textSecondary),
      title: Text(label, style: TextStyle(color: effective)),
      trailing: const Icon(Icons.chevron_right,
          color: AppColors.textSecondary),
      onTap: onTap,
    );
  }
}
