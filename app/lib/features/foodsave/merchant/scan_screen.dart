import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/session/session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../data/foodsave_api.dart';
import '../widgets/foodsave_ui.dart';
import 'scan_result_view.dart';
import 'widgets/scan_frame_overlay.dart';

/// Builds the camera preview; calls [onCode] for each decoded QR payload.
/// Injected in tests so the real camera is never instantiated.
typedef ScannerViewBuilder = Widget Function(
    BuildContext context, ValueChanged<String> onCode);

/// Merchant pickup validation: scans the client's QR code (or accepts a
/// manually entered code) and shows the server's verdict full screen.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.session, this.scannerBuilder});

  final SessionController session;

  /// Test hook: replaces the `mobile_scanner` camera view.
  final ScannerViewBuilder? scannerBuilder;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  static const Duration _dedupeWindow = Duration(seconds: 3);

  late final FoodSaveApi _api = FoodSaveApi(widget.session.api);
  MobileScannerController? _controller;

  bool _busy = false;
  ScanResultDto? _result;
  String? _lastCode;
  DateTime? _lastAt;

  @override
  void initState() {
    super.initState();
    if (widget.scannerBuilder == null) {
      _controller = MobileScannerController(
        formats: const [BarcodeFormat.qrCode],
        detectionSpeed: DetectionSpeed.normal,
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _camera(Future<void> Function(MobileScannerController c) action) {
    final c = _controller;
    if (c == null) return;
    unawaited(action(c).catchError((Object e) {
      developer.log('camera action failed', name: 'foodsave', error: e);
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
      showFoodSaveError(context, e);
      _camera((c) => c.start());
    }
  }

  void _scanAgain() {
    setState(() {
      _result = null;
      _lastAt = DateTime.now(); // keeps the previous code ignored for 3 s
    });
    _camera((c) => c.start());
  }

  Future<void> _manualEntry() async {
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ManualCodeSheet(),
    );
    if (code != null && mounted) await _submit(code, manual: true);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: result == null ? Colors.black : AppColors.background,
        foregroundColor: result == null ? Colors.white : AppColors.text,
        title: Text(result == null ? 'Scanner un retrait' : 'Résultat du scan'),
        actions: [
          if (result == null && _controller != null)
            _TorchButton(controller: _controller!),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: widget.scannerBuilder != null
                ? widget.scannerBuilder!(context, _submit)
                : MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                    errorBuilder: (context, error) => _CameraError(
                        error: error, onManualEntry: _manualEntry),
                  ),
          ),
          Positioned.fill(child: ScanFrameOverlay(busy: _busy)),
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: 0,
            child: SafeArea(
              minimum: const EdgeInsets.only(bottom: AppSpacing.md),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.text,
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: _busy ? null : _manualEntry,
                icon: const Icon(Icons.keyboard_outlined),
                label: const Text('Saisir le code'),
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: FoodSaveMotion.medium,
              switchInCurve: FoodSaveMotion.curve,
              switchOutCurve: FoodSaveMotion.curve,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween(begin: 0.96, end: 1.0).animate(animation),
                  child: child,
                ),
              ),
              child: result == null
                  ? const SizedBox.shrink()
                  : ScanResultView(
                      key: ValueKey(result),
                      result: result,
                      onScanAgain: _scanAgain,
                      onDone: () => Navigator.of(context).maybePop(),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TorchButton extends StatelessWidget {
  const _TorchButton({required this.controller});

  final MobileScannerController controller;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: controller,
        builder: (context, state, _) {
          final torch = state.torchState;
          if (!state.isInitialized || torch == TorchState.unavailable) {
            return const SizedBox.shrink();
          }
          final on = torch == TorchState.on;
          return IconButton(
            tooltip: on ? 'Éteindre la lampe' : 'Allumer la lampe',
            isSelected: on,
            icon: Icon(on ? Icons.flash_on : Icons.flash_off),
            color: on ? AppColors.accent : Colors.white,
            onPressed: () => controller.toggleTorch().catchError((Object e) {
              developer.log('torch failed', name: 'foodsave', error: e);
            }),
          );
        },
      );
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
          'Autorisez l\'accès à la caméra dans les réglages de votre téléphone, ou saisissez le code du client manuellement.'
        ),
      MobileScannerErrorCode.unsupported => (
          Icons.videocam_off_outlined,
          'Aucune caméra disponible',
          'Cet appareil ne permet pas de scanner : saisissez le code du client manuellement.'
        ),
      _ => (
          Icons.videocam_off_outlined,
          'Caméra indisponible',
          'La caméra n\'a pas pu démarrer. Fermez les autres applications qui l\'utilisent, ou saisissez le code manuellement.'
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
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.moduleFoodSave.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child:
                    Icon(icon, color: AppColors.moduleFoodSaveDeep, size: 34),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                style: foodSaveFilledStyle(),
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

/// Manual fallback (emulator without camera, damaged screen…).
class _ManualCodeSheet extends StatefulWidget {
  const _ManualCodeSheet();

  @override
  State<_ManualCodeSheet> createState() => _ManualCodeSheetState();
}

class _ManualCodeSheetState extends State<_ManualCodeSheet> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _validate() {
    final code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Saisissez ou collez le code affiché par le client');
      return;
    }
    Navigator.pop(context, code);
  }

  Future<void> _paste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text == null || text.isEmpty || !mounted) return;
      _controller.text = text;
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
      setState(() => _error = null);
    } on PlatformException catch (e) {
      developer.log('clipboard failed', name: 'foodsave', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Saisir le code de retrait',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Utile si la caméra est indisponible : collez ou saisissez le code de la réservation transmis par le client.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.textSecondaryStrong),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const ValueKey('manual-code-field'),
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _validate(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              labelText: 'Code de retrait',
              hintText: 'FS1.…',
              errorText: _error,
              suffixIcon: IconButton(
                tooltip: 'Coller le code',
                icon: const Icon(Icons.content_paste),
                onPressed: _paste,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            style: foodSaveFilledStyle(),
            onPressed: _validate,
            icon: const Icon(Icons.verified_outlined),
            label: const Text('Valider le retrait'),
          ),
        ],
      ),
    );
  }
}
