import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import 'core/api/api_client.dart';
import 'core/notifications/notification_service.dart';
import 'core/session/session_controller.dart';
import 'core/session/stores.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/home/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = SessionController(
    api: ApiClient(),
    tokenStore: SecureTokenStore(),
    settings: SharedPrefsSettingsStore(),
  );
  await NotificationService.instance.init();
  runApp(ProxiLifeApp(session: session));
}

class ProxiLifeApp extends StatelessWidget {
  const ProxiLifeApp({super.key, required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ProxiLife',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: SplashGate(session: session),
    );
  }
}

/// Decides between the login flow and the home shell. When biometrics are
/// enabled, the stored session is only accepted after a biometric prompt.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.session});

  final SessionController session;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  late final Future<void> _startupFuture = _startup();

  Future<void> _startup() async {
    await widget.session.restore();
    if (widget.session.status == SessionStatus.authenticated &&
        widget.session.biometricsEnabled) {
      final auth = LocalAuthentication();
      try {
        final ok = await auth.authenticate(
          localizedReason: 'Déverrouillez ProxiLife pour continuer',
          biometricOnly: true,
          persistAcrossBackgrounding: true,
        );
        if (!ok) {
          await widget.session.logout();
        }
      } on LocalAuthException {
        // No biometrics on this device: silently fall back to password.
        await widget.session.setBiometricsEnabled(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _startupFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: AppColors.balanceCardGradient,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.eco,
                        color: Colors.white, size: 38),
                  ),
                  const SizedBox(height: 24),
                  Text('ProxiLife',
                      style:
                          Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 16),
                  const CircularProgressIndicator(),
                ],
              ),
            ),
          );
        }
        return ListenableBuilder(
          listenable: widget.session,
          builder: (context, _) {
            if (widget.session.status == SessionStatus.authenticated) {
              return MainShell(session: widget.session);
            }
            return LoginScreen(session: widget.session);
          },
        );
      },
    );
  }
}
