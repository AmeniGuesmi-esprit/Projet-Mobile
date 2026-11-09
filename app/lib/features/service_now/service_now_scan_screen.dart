import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/widgets/primary_button.dart';

/// Reads the client's presence code with the camera, or typed by hand.
/// Pops with the code.
class ServiceNowScanScreen extends StatefulWidget {
  const ServiceNowScanScreen({super.key});

  @override
  State<ServiceNowScanScreen> createState() => _ServiceNowScanScreenState();
}

class _ServiceNowScanScreenState extends State<ServiceNowScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
  );
  final TextEditingController _code = TextEditingController();
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    _code.dispose();
    super.dispose();
  }

  void _finish(String value) {
    final code = value.trim();
    if (code.isEmpty || _done) return;
    _done = true;
    Navigator.of(context).pop(code);
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        _finish(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Code de présence')),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                errorBuilder: (context, error) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      'Caméra indisponible : saisissez le code ci-dessous.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                children: [
                  TextField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Ou saisissez le code du client',
                    ),
                    onSubmitted: _finish,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  PrimaryButton(
                    label: 'Valider',
                    onPressed: () => _finish(_code.text),
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
