import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/session/session_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/verification_code_input.dart';

class VerifyScreen extends StatefulWidget {
  const VerifyScreen({
    super.key,
    required this.session,
    required this.email,
    this.sendInitialCode = false,
  });

  final SessionController session;
  final String email;

  /// When arriving from the login screen (unverified account), resend a code
  /// on first show.
  final bool sendInitialCode;

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  final GlobalKey<VerificationCodeInputState> _codeKey =
      GlobalKey<VerificationCodeInputState>();

  bool _loading = false;
  bool _resending = false;
  String? _error;
  int _countdown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.sendInitialCode) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _resend(silent: true));
    } else {
      _startCountdown();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _countdown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _countdown--;
        if (_countdown <= 0) t.cancel();
      });
    });
  }

  Future<void> _resend({bool silent = false}) async {
    if (_countdown > 0 && !silent) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await widget.session.resendCode(widget.email);
      if (!mounted) return;
      _startCountdown();
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nouveau code envoyé par e-mail')),
        );
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _verify(String code) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.session.verify(widget.email, code);
      await NotificationService.instance.show(
        title: 'Compte vérifié',
        body: 'Bienvenue sur ProxiLife ! Connectez-vous pour commencer.',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compte vérifié, connectez-vous')),
      );
      // Back to the login screen (root).
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
      _codeKey.currentState?.clear();
    } catch (_) {
      setState(() => _error = 'Une erreur est survenue, veuillez réessayer');
      _codeKey.currentState?.clear();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Vérification')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mark_email_read_outlined,
                  color: AppColors.primary, size: 32),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Vérifiez votre e-mail',
                style: theme.textTheme.headlineMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Nous avons envoyé un code à 6 chiffres à\n${widget.email}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xxl),
            VerificationCodeInput(
              key: _codeKey,
              enabled: !_loading,
              onCompleted: _verify,
            ),
            const SizedBox(height: AppSpacing.md),
            if (_error != null) ...[
              Text(
                _error!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              Center(
                child: _countdown > 0
                    ? Text(
                        'Renvoyer le code dans ${_countdown}s',
                        style: theme.textTheme.bodyMedium,
                      )
                    : TextButton(
                        onPressed: _resending ? null : _resend,
                        child: Text(_resending
                            ? 'Envoi en cours…'
                            : 'Renvoyer le code'),
                      ),
              ),
            const SizedBox(height: AppSpacing.xxl),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.terminal,
                      color: AppColors.text, size: 18),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'En mode développement, le code s\'affiche aussi dans le terminal du serveur local.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.text),
                    ),
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
