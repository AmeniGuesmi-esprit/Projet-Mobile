import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/session/session_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/primary_button.dart';
import '../reservations/reservation_api.dart';
import '../trips/trip_labels.dart';
import 'ble_boarding.dart';

class _UserMessage implements Exception {
  const _UserMessage(this.message);
  final String message;
}

/// Passenger: confirms boarding by scanning the driver's QR code or by
/// listening to his Bluetooth broadcast. Pops `true` when confirmed.
class PassengerBoardingScreen extends StatefulWidget {
  const PassengerBoardingScreen({
    super.key,
    required this.session,
    required this.reservation,
  });

  final SessionController session;
  final TripReservationDto reservation;

  @override
  State<PassengerBoardingScreen> createState() =>
      _PassengerBoardingScreenState();
}

class _PassengerBoardingScreenState extends State<PassengerBoardingScreen> {
  late final ReservationApi _api = ReservationApi(widget.session.api);
  final BleBoardingScanner _ble = BleBoardingScanner();
  bool _busy = false;
  bool _done = false;
  String? _error;
  String? _status;

  Future<Position> _position() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const _UserMessage('Activez la localisation de votre téléphone');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const _UserMessage(
          'La localisation est nécessaire pour confirmer l\'embarquement');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      await action();
    } on _UserMessage catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm(String code, BoardingMethod method) async {
    setState(() => _status = 'Vérification de votre position…');
    final pos = await _position();
    await _api.confirmBoarding(
      reservationId: widget.reservation.id,
      code: code,
      method: method,
      lat: pos.latitude,
      lng: pos.longitude,
    );
    if (!mounted) return;
    setState(() => _done = true);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _scanQr() => _run(() async {
        final raw = await Navigator.of(context).push<String>(
          MaterialPageRoute<String>(builder: (_) => const _QrScanPage()),
        );
        if (raw == null) return;
        final code = BoardingCodeDto.codeFromPayload(
            raw, widget.reservation.trajet.id);
        if (code == null) {
          throw const _UserMessage(
              'Ce QR code ne correspond pas à votre trajet');
        }
        await _confirm(code, BoardingMethod.qr);
      });

  Future<void> _scanBluetooth() => _run(() async {
        setState(() => _status = 'Recherche du véhicule par Bluetooth…');
        final code = await _ble.findCode(widget.reservation.trajet.id);
        if (code == null) {
          throw const _UserMessage(
              'Véhicule introuvable. Le conducteur doit activer la diffusion Bluetooth, ou utilisez le QR code.');
        }
        await _confirm(code, BoardingMethod.bluetooth);
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trip = widget.reservation.trajet;
    return Scaffold(
      appBar: AppBar(title: const Text('Je suis monté')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: _done
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle,
                          size: 72, color: AppColors.success),
                      const SizedBox(height: AppSpacing.md),
                      Text('Embarquement confirmé',
                          style: theme.textTheme.titleLarge),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${trip.departAdresse} → ${trip.arriveeAdresse}',
                        style: theme.textTheme.titleMedium),
                    Text(
                      '${trip.vehicule.libelle} · ${formatTripTime(trip.dateHeureDepart)} · avec ${trip.conducteurNom}',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Vérifiez que vous êtes dans le bon véhicule, puis scannez le QR code affiché sur le téléphone du conducteur.',
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    PrimaryButton(
                      label: 'Scanner le QR code',
                      icon: Icons.qr_code_scanner,
                      onPressed: _busy ? null : _scanQr,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _scanBluetooth,
                      icon: const Icon(Icons.bluetooth_searching),
                      label: const Text('Utiliser le Bluetooth'),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    if (_busy)
                      Row(
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(_status ?? 'Veuillez patienter…',
                                style: theme.textTheme.bodyMedium),
                          ),
                        ],
                      ),
                    if (_error != null)
                      Text(_error!,
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(color: AppColors.error)),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Full-screen camera; pops with the first QR code content read.
class _QrScanPage extends StatefulWidget {
  const _QrScanPage();

  @override
  State<_QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<_QrScanPage> {
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        _handled = true;
        Navigator.of(context).pop(raw);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scanner le QR code')),
      body: MobileScanner(onDetect: _onDetect),
    );
  }
}
