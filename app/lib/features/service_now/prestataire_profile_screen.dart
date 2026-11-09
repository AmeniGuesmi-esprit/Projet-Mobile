import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/session/session_controller.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/primary_button.dart';
import '../reservations/reservation_api.dart' show apiErrorMessage;
import 'service_now_api.dart';
import 'service_now_format.dart';
import 'service_now_location.dart';

/// Specialties and base location of a prestataire, used by smart matching.
class PrestataireProfileScreen extends StatefulWidget {
  const PrestataireProfileScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<PrestataireProfileScreen> createState() =>
      _PrestataireProfileScreenState();
}

class _PrestataireProfileScreenState extends State<PrestataireProfileScreen> {
  late final ServiceNowApi _api = ServiceNowApi(widget.session.api);
  final Set<ServiceNowType> _selected = {};
  double? _latitude;
  double? _longitude;
  bool _loading = true;
  bool _saving = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _load() async {
    try {
      final profile = await _api.profile();
      if (!mounted) return;
      setState(() {
        _selected
          ..clear()
          ..addAll(profile.specialites);
        _latitude = profile.latitude;
        _longitude = profile.longitude;
      });
    } catch (e) {
      if (mounted) _snack(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _useCurrentPosition() async {
    setState(() => _locating = true);
    final position = await locateWithConsent(
      context,
      'Votre position sert à vous proposer les demandes les plus proches.',
    );
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (position != null) {
        _latitude = position.latitude;
        _longitude = position.longitude;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _api.saveProfile(PrestataireProfilDto(
        specialites: _selected,
        latitude: _latitude,
        longitude: _longitude,
      ));
      if (!mounted) return;
      _snack('Profil enregistré');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _snack(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil de prestataire')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  Text('Mes spécialités', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final type in ServiceNowType.values)
                        FilterChip(
                          avatar: Icon(serviceTypeIcon(type), size: 18),
                          showCheckmark: false,
                          label: Text(type.label),
                          selected: _selected.contains(type),
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _selected.add(type);
                            } else {
                              _selected.remove(type);
                            }
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Ma zone de travail',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Les demandes proches de ce point apparaissent en premier.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _locating ? null : _useCurrentPosition,
                      icon: Icon(_latitude == null
                          ? Icons.my_location
                          : Icons.check_circle),
                      label: Text(_latitude == null
                          ? 'Utiliser ma position actuelle'
                          : 'Position enregistrée : la mettre à jour'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  PrimaryButton(
                    label: 'Enregistrer',
                    isLoading: _saving,
                    onPressed: _save,
                  ),
                ],
              ),
            ),
    );
  }
}
