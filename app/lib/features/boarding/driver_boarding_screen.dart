import 'dart:async';

import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/session/session_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../reservations/reservation_api.dart';
import '../trips/trip_labels.dart';
import 'ble_boarding.dart';

/// Driver: shows the rotating boarding QR code (and can broadcast it over
/// Bluetooth) and lists the accepted passengers with their boarding status.
class DriverBoardingScreen extends StatefulWidget {
  const DriverBoardingScreen({
    super.key,
    required this.session,
    required this.trip,
  });

  final SessionController session;
  final TripDto trip;

  @override
  State<DriverBoardingScreen> createState() => _DriverBoardingScreenState();
}

class _DriverBoardingScreenState extends State<DriverBoardingScreen> {
  late final ReservationApi _api = ReservationApi(widget.session.api);
  final BleBoardingBroadcaster _ble = BleBoardingBroadcaster();

  BoardingCodeDto? _code;
  String? _error;
  String? _bleError;
  bool _loading = false;
  bool _bluetooth = false;
  int _remaining = 0;
  List<TripReservationDto> _passengers = const [];
  Timer? _tick;
  Timer? _listTimer;

  @override
  void initState() {
    super.initState();
    _loadCode();
    _loadPassengers();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_code == null || _error != null || !mounted) return;
      setState(() => _remaining = _remaining > 0 ? _remaining - 1 : 0);
      if (_remaining <= 0 && !_loading) _loadCode();
    });
    _listTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _loadPassengers(),
    );
  }

  @override
  void dispose() {
    _tick?.cancel();
    _listTimer?.cancel();
    _ble.stop();
    super.dispose();
  }

  Future<void> _loadCode() async {
    _loading = true;
    try {
      final c = await _api.boardingCode(widget.trip.id);
      if (!mounted) return;
      setState(() {
        _code = c;
        _remaining = c.expiresInSeconds;
        _error = null;
      });
      if (_bluetooth) await _broadcast(c);
    } catch (e) {
      if (mounted) {
        setState(() {
          _code = null;
          _error = apiErrorMessage(e);
        });
      }
    } finally {
      _loading = false;
    }
  }

  Future<void> _loadPassengers() async {
    try {
      final all = await _api.received();
      if (!mounted) return;
      setState(() {
        _passengers = all
            .where((r) =>
                r.trajet.id == widget.trip.id &&
                r.statut == TripReservationStatus.acceptee)
            .toList();
      });
    } catch (_) {
      // Keep the previous list.
    }
  }

  Future<void> _broadcast(BoardingCodeDto c) async {
    try {
      await _ble.start(c);
      if (mounted) setState(() => _bleError = null);
    } catch (_) {
      if (mounted) {
        setState(() {
          _bluetooth = false;
          _bleError = 'Bluetooth indisponible : utilisez le QR code';
        });
      }
    }
  }

  Future<void> _toggleBluetooth(bool on) async {
    setState(() {
      _bluetooth = on;
      _bleError = null;
    });
    if (!on) {
      await _ble.stop();
    } else if (_code != null) {
      await _broadcast(_code!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trip = widget.trip;
    final code = _code;
    return Scaffold(
      appBar: AppBar(title: const Text('Embarquement')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Text('${trip.departAdresse} → ${trip.arriveeAdresse}',
                style: theme.textTheme.titleMedium),
            Text(
              '${formatTripDate(trip.dateHeureDepart)} · ${formatTripTime(trip.dateHeureDepart)}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            if (_error != null) ...[
              Text(_error!,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: AppColors.error)),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: _loadCode,
                child: const Text('Réessayer'),
              ),
            ] else if (code == null) ...[
              const Center(child: CircularProgressIndicator()),
            ] else ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.outlineSoft),
                  ),
                  child: QrImageView(
                    data: code.payload,
                    size: 240,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: Text(
                  code.code,
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(letterSpacing: 4),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              LinearProgressIndicator(
                value: code.stepSeconds == 0
                    ? 0
                    : _remaining / code.stepSeconds,
              ),
              const SizedBox(height: AppSpacing.xs),
              Center(
                child: Text('Le code change dans $_remaining s',
                    style: theme.textTheme.bodyMedium),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Demandez au passager de scanner ce QR code une fois installé dans votre véhicule.',
                style: theme.textTheme.bodyMedium,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Diffuser aussi par Bluetooth'),
                subtitle: _bleError == null ? null : Text(_bleError!),
                value: _bluetooth,
                onChanged: _toggleBluetooth,
              ),
            ],
            const Divider(height: AppSpacing.xxl),
            Text('Passagers', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            if (_passengers.isEmpty)
              Text('Aucun passager accepté pour ce trajet.',
                  style: theme.textTheme.bodyMedium)
            else
              for (final r in _passengers)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    r.estEmbarque
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: r.estEmbarque
                        ? AppColors.success
                        : AppColors.textSecondary,
                  ),
                  title: Text(r.passagerNom),
                  subtitle: Text(r.estEmbarque
                      ? 'Embarqué (${r.embarqueMethode == BoardingMethod.bluetooth ? 'Bluetooth' : 'QR code'})'
                      : '${r.nbPlaces} place(s) · pas encore embarqué'),
                ),
          ],
        ),
      ),
    );
  }
}
