import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../data/coach_api.dart';
import '../../domain/step_detector.dart';
import '../coach_theme.dart';
import 'coach_format.dart';
import 'coach_widgets.dart';

/// « Mon suivi » of a session whose presence was validated:
///  - steps read from the phone's motion sensor (accelerometer), or typed;
///  - heart rate typed by the client (BPM);
///  - saved on the booking (`PUT /coach/reservations/<id>/suivi`).
class CoachTrackingCard extends StatefulWidget {
  const CoachTrackingCard({
    super.key,
    required this.booking,
    required this.api,
    required this.onSaved,
  });

  final CoachBookingDto booking;
  final CoachApi api;

  /// Called with the updated booking once the server saved the tracking.
  final ValueChanged<CoachBookingDto> onSaved;

  @override
  State<CoachTrackingCard> createState() => _CoachTrackingCardState();
}

class _CoachTrackingCardState extends State<CoachTrackingCard> {
  final StepDetector _detector = StepDetector();
  StreamSubscription<AccelerometerEvent>? _subscription;

  late final TextEditingController _stepsController = TextEditingController(
      text: widget.booking.pas?.toString() ?? '');
  late final TextEditingController _bpmController = TextEditingController(
      text: widget.booking.frequenceCardiaque?.toString() ?? '');

  bool _counting = false;
  bool _saving = false;
  String? _error;
  String? _sensorMessage;

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _stepsController.dispose();
    _bpmController.dispose();
    super.dispose();
  }

  int? get _steps => int.tryParse(_stepsController.text.trim());

  void _startCounting() {
    _detector.reset();
    final base = _steps ?? 0; // keep counting from what is already typed
    try {
      _subscription = accelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 40),
      ).listen(
        (event) {
          if (!mounted) return;
          if (_detector.addSample(event.x, event.y, event.z, DateTime.now())) {
            setState(() => _stepsController.text = '${base + _detector.steps}');
          }
        },
        onError: (Object _) {
          _stopCounting();
          if (mounted) {
            setState(() => _sensorMessage =
                'Capteur de mouvement indisponible : saisissez vos pas à la main.');
          }
        },
      );
      setState(() {
        _counting = true;
        _sensorMessage = null;
        _error = null;
      });
    } catch (_) {
      setState(() => _sensorMessage =
          'Capteur de mouvement indisponible : saisissez vos pas à la main.');
    }
  }

  void _stopCounting() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    if (mounted && _counting) setState(() => _counting = false);
  }

  Future<void> _save() async {
    final steps = _steps;
    final bpmText = _bpmController.text.trim();
    final bpm = bpmText.isEmpty ? null : int.tryParse(bpmText);
    final problem =
        CoachRules.validateMetrics(pas: steps, frequenceCardiaque: bpm);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    _stopCounting();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.api
          .saveMetrics(widget.booking.id, pas: steps, frequenceCardiaque: bpm);
      if (!mounted) return;
      setState(() => _saving = false);
      widget.onSaved(saved);
      showCoachSnack(context, 'Suivi enregistré');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = coachErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = widget.booking;
    final steps = _steps;
    final km = steps == null ? null : CoachRules.distanceKmFromSteps(steps);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.monitor_heart_outlined,
                    color: CoachColors.brandDeep),
                const SizedBox(width: AppSpacing.xs),
                Text('Mon suivi', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: CoachStatTile(
                    icon: Icons.directions_walk,
                    value: b.pas?.toString() ?? '—',
                    label: 'pas',
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: CoachStatTile(
                    icon: Icons.route_outlined,
                    value: b.distanceKm == null ? '—' : coachKm(b.distanceKm!),
                    label: 'distance',
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: CoachStatTile(
                    icon: Icons.favorite_border,
                    value: b.frequenceCardiaque?.toString() ?? '—',
                    label: 'BPM',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _stepsController,
              readOnly: _counting,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Nombre de pas',
                prefixIcon: const Icon(Icons.directions_walk),
                helperText: km == null
                    ? null
                    : 'Environ ${coachKm(km)} parcourus',
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            OutlinedButton.icon(
              onPressed: _saving
                  ? null
                  : (_counting ? _stopCounting : _startCounting),
              icon: Icon(_counting ? Icons.stop_circle_outlined : Icons.sensors),
              label: Text(_counting
                  ? 'Arrêter le comptage'
                  : 'Compter mes pas avec le capteur'),
            ),
            if (_counting)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'Gardez le téléphone sur vous pendant la séance.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (_sensorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  _sensorMessage!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.error),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _bpmController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Fréquence cardiaque (BPM)',
                prefixIcon: Icon(Icons.favorite_border),
                helperText: 'Mesurée avec votre montre ou à la main',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  _error!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.error),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              label: 'Enregistrer mon suivi',
              icon: Icons.save_outlined,
              isLoading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
