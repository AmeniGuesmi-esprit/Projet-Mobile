import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/coach_api.dart';
import '../coach_theme.dart';
import '../widgets/coach_format.dart';
import '../widgets/coach_widgets.dart';

/// Coach: scan a client's QR code to validate his presence (and confirm a
/// cash payment). The code can also be typed when the camera is unavailable.
class CoachScanScreen extends StatefulWidget {
  const CoachScanScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<CoachScanScreen> createState() => _CoachScanScreenState();
}

class _CoachScanScreenState extends State<CoachScanScreen> {
  static const Duration _dedupeWindow = Duration(seconds: 3);

  late final CoachApi _api = CoachApi(widget.session.api);
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
  );

  bool _busy = false;
  CoachScanResultDto? _result;
  String? _lastCode;
  DateTime? _lastAt;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _camera(Future<void> Function(MobileScannerController c) action) {
    unawaited(action(_controller).catchError((Object e) {
      developer.log('camera action failed', name: 'coach', error: e);
    }));
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        _submit(value);
        return;
      }
    }
  }

  Future<void> _submit(String raw, {bool manual = false}) async {
    final token = raw.trim();
    if (token.isEmpty || _busy || _result != null) return;
    final now = DateTime.now();
    if (!manual &&
        token == _lastCode &&
        _lastAt != null &&
        now.difference(_lastAt!) < _dedupeWindow) {
      return; // same code still in front of the camera
    }
    _lastCode = token;
    _lastAt = now;
    setState(() => _busy = true);
    _camera((c) => c.pause());
    try {
      final result = await _api.scan(token);
      if (!mounted) return;
      setState(() {
        _result = result;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showCoachSnack(context, coachErrorMessage(e));
      _camera((c) => c.start());
    }
  }

  void _scanNext() {
    setState(() {
      _result = null;
      _lastCode = null;
    });
    _camera((c) => c.start());
  }

  Future<void> _manualEntry() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _ManualCodeDialog(),
    );
    if (code != null && code.trim().isNotEmpty) {
      await _submit(code, manual: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanner une présence'),
        actions: [
          IconButton(
            tooltip: 'Saisir le code à la main',
            onPressed: _busy || result != null ? null : _manualEntry,
            icon: const Icon(Icons.keyboard_outlined),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) => _CameraError(
                error: error,
                onManualEntry: _manualEntry,
              ),
            ),
          ),
          if (result == null)
            const Positioned.fill(
              child: IgnorePointer(child: CustomPaint(painter: _FramePainter())),
            ),
          if (result == null)
            Positioned(
              left: AppSpacing.md,
              right: AppSpacing.md,
              bottom: AppSpacing.xl,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      if (_busy)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      else
                        const Icon(Icons.qr_code_2, color: Colors.white),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          _busy
                              ? 'Vérification du code…'
                              : 'Placez le QR code du client dans le cadre',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (result != null)
            Positioned.fill(
              child: ColoredBox(
                color: AppColors.background,
                child: _ResultPanel(result: result, onNext: _scanNext),
              ),
            ),
        ],
      ),
    );
  }
}

/// Dimmed background with a square window and a white border.
class _FramePainter extends CustomPainter {
  const _FramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide * 0.7;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: side,
      height: side,
    );
    final window = RRect.fromRectAndRadius(rect, const Radius.circular(20));
    final scrim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(window);
    canvas.drawPath(scrim, Paint()..color = Colors.black54);
    canvas.drawRRect(
      window,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.result, required this.onNext});

  final CoachScanResultDto result;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = result.reservation;
    final s = b.seance;
    final already = result.dejaPresent;
    final color = already ? AppColors.info : AppColors.success;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.lg),
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                already ? Icons.info_outline : Icons.check_circle,
                color: color,
                size: 52,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              already ? 'Présence déjà validée' : 'Présence validée',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(b.clientNom,
                style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            if (s != null) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text('${s.titre} · ${coachWhen(s.dateHeure)}',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center),
            ],
            if (result.especesEncaissees) ...[
              const SizedBox(height: AppSpacing.md),
              CoachChip(
                label: 'Espèces encaissées : ${coachPrice(b.montantCentimes)}',
                color: AppColors.success,
                icon: Icons.payments_outlined,
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: onNext,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scanner un autre client'),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Terminer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error, required this.onManualEntry});

  final MobileScannerException error;
  final VoidCallback onManualEntry;

  @override
  Widget build(BuildContext context) {
    final (icon, title, message) = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied => (
          Icons.no_photography_outlined,
          'Accès à la caméra refusé',
          'Autorisez l\'accès à la caméra dans les réglages de votre téléphone, ou saisissez le code du client à la main.'
        ),
      MobileScannerErrorCode.unsupported => (
          Icons.videocam_off_outlined,
          'Aucune caméra disponible',
          'Cet appareil ne permet pas de scanner (c\'est le cas de beaucoup d\'émulateurs) : saisissez le code du client à la main.'
        ),
      _ => (
          Icons.videocam_off_outlined,
          'Caméra indisponible',
          'La caméra n\'a pas pu démarrer. Fermez les autres applications qui l\'utilisent, ou saisissez le code à la main.'
        ),
    };
    return ColoredBox(
      color: AppColors.background,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: CoachColors.brandDeep),
              const SizedBox(height: AppSpacing.md),
              Text(title,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.xs),
              Text(message,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: onManualEntry,
                icon: const Icon(Icons.keyboard_outlined),
                label: const Text('Saisir le code'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dialog to type (or paste) the code shown under the client's QR code.
class _ManualCodeDialog extends StatefulWidget {
  const _ManualCodeDialog();

  @override
  State<_ManualCodeDialog> createState() => _ManualCodeDialogState();
}

class _ManualCodeDialogState extends State<_ManualCodeDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Saisir le code'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 1,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Code du QR',
          hintText: 'Collez le code de la réservation',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Valider'),
        ),
      ],
    );
  }
}
