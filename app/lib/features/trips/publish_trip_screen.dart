import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/api/api_client.dart';
import '../../core/location/geocoding_service.dart';
import '../../core/session/session_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/primary_button.dart';
import '../payment/payment_api.dart';
import 'trip_api.dart';
import 'trip_labels.dart';
import 'widgets/place_field.dart';

/// "Déposer un trajet" (driver). Pops `true` when a trip was published.
class PublishTripScreen extends StatefulWidget {
  const PublishTripScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<PublishTripScreen> createState() => _PublishTripScreenState();
}

class _PublishTripScreenState extends State<PublishTripScreen> {
  final _formKey = GlobalKey<FormState>();
  final _priceController = TextEditingController();
  final _geocoder = GeocodingService();
  late final TripApi _api = TripApi(widget.session.api);

  List<VehicleDto> _vehicles = const [];
  bool _vehiclesLoading = true;
  String? _vehiclesError;
  int? _vehicleId;
  int _vehicleSeats = TripRules.maxSeats;

  GeoPlace? _depart;
  GeoPlace? _arrivee;
  DateTime? _date;
  TimeOfDay? _time;
  int _places = 1;
  Ambiance _ambiance = Ambiance.indifferent;
  bool _fumeur = false;
  bool _animaux = false;
  bool _femmes = false;

  bool _submitted = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ vehicles --

  void _selectVehicle(VehicleDto? vehicle) {
    _vehicleId = vehicle?.id;
    _vehicleSeats = vehicle?.nbPlaces ?? TripRules.maxSeats;
    if (_places > _vehicleSeats) _places = _vehicleSeats;
  }

  Future<void> _loadVehicles({int? select}) async {
    try {
      final list = await _api.listVehicles();
      if (!mounted) return;
      setState(() {
        _vehicles = list;
        final wanted = select ?? _vehicleId;
        VehicleDto? chosen;
        for (final v in list) {
          if (v.id == wanted) chosen = v;
        }
        chosen ??= list.isEmpty ? null : list.first;
        _selectVehicle(chosen);
        _vehiclesError = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _vehiclesError = e.message);
    } finally {
      if (mounted) setState(() => _vehiclesLoading = false);
    }
  }

  Future<void> _addVehicle() async {
    final created = await showDialog<VehicleDto>(
      context: context,
      builder: (_) => _AddVehicleDialog(api: _api),
    );
    if (created != null) await _loadVehicles(select: created.id);
  }

  // ---------------------------------------------------------- date/time --

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Date du départ',
      cancelText: 'Annuler',
      confirmText: 'OK',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 8, minute: 0),
      helpText: 'Heure du départ',
      cancelText: 'Annuler',
      confirmText: 'OK',
    );
    if (picked != null) setState(() => _time = picked);
  }

  // -------------------------------------------------------------- submit --

  Future<void> _submit() async {
    setState(() {
      _submitted = true;
      _error = null;
    });
    final formOk = _formKey.currentState!.validate();
    final depart = _depart;
    final arrivee = _arrivee;
    final date = _date;
    final time = _time;
    final vehicleId = _vehicleId;
    if (!formOk ||
        depart == null ||
        arrivee == null ||
        date == null ||
        time == null) {
      return;
    }
    if (vehicleId == null) {
      setState(() => _error = 'Ajoutez d\'abord un véhicule');
      return;
    }
    final cents = parseAmountToCents(_priceController.text);
    if (cents == null) return;

    final when =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!when.isAfter(DateTime.now())) {
      setState(() => _error = 'Le départ doit être dans le futur');
      return;
    }
    final distance = TripRules.distanceKm(depart.latitude, depart.longitude,
        arrivee.latitude, arrivee.longitude);
    if (distance < TripRules.minTripDistanceKm) {
      setState(() => _error = 'Le départ et l\'arrivée sont identiques');
      return;
    }

    setState(() => _loading = true);
    try {
      await _api.publish(
        vehiculeId: vehicleId,
        departAdresse: depart.label,
        departLatitude: depart.latitude,
        departLongitude: depart.longitude,
        arriveeAdresse: arrivee.label,
        arriveeLatitude: arrivee.latitude,
        arriveeLongitude: arrivee.longitude,
        dateHeureDepart: when,
        places: _places,
        prixParPlaceCentimes: cents,
        ambiance: _ambiance,
        fumeurAccepte: _fumeur,
        animauxAcceptes: _animaux,
        reserveAuxFemmes: _femmes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trajet publié')),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Une erreur est survenue, veuillez réessayer');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // --------------------------------------------------------------- build --

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Déposer un trajet')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              PlaceField(
                label: 'Départ',
                icon: Icons.trip_origin,
                value: _depart,
                geocoder: _geocoder,
                allowCurrentLocation: true,
                errorText: _submitted && _depart == null
                    ? 'Choisissez un départ (loupe ou « ma position »)'
                    : null,
                onChanged: (p) => setState(() => _depart = p),
              ),
              const SizedBox(height: AppSpacing.md),
              PlaceField(
                label: 'Arrivée',
                icon: Icons.flag_outlined,
                value: _arrivee,
                geocoder: _geocoder,
                errorText: _submitted && _arrivee == null
                    ? 'Choisissez une arrivée avec la loupe'
                    : null,
                onChanged: (p) => setState(() => _arrivee = p),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _PickerField(
                      icon: Icons.calendar_today_outlined,
                      label: 'Date',
                      value: _date == null ? null : formatTripDate(_date!),
                      errorText:
                          _submitted && _date == null ? 'Requise' : null,
                      onTap: _pickDate,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _PickerField(
                      icon: Icons.schedule,
                      label: 'Heure',
                      value: _time == null
                          ? null
                          : '${_time!.hour.toString().padLeft(2, '0')}:'
                              '${_time!.minute.toString().padLeft(2, '0')}',
                      errorText:
                          _submitted && _time == null ? 'Requise' : null,
                      onTap: _pickTime,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('Véhicule', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              _buildVehicles(theme),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: Text('Places proposées',
                        style: theme.textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip: 'Moins',
                    onPressed: _places > 1
                        ? () => setState(() => _places--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$_places', style: theme.textTheme.titleLarge),
                  IconButton(
                    tooltip: 'Plus',
                    onPressed: _places < _vehicleSeats
                        ? () => setState(() => _places++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Prix par place (DT)',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (v) {
                  final cents = parseAmountToCents(v ?? '');
                  if (cents == null) return 'Prix positif requis';
                  return TripRules.priceError(cents);
                },
              ),
              const SizedBox(height: AppSpacing.xl),
              Text('Préférences de voyage', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final a in Ambiance.values)
                    ChoiceChip(
                      label: Text(a.label),
                      selected: _ambiance == a,
                      onSelected: (_) => setState(() => _ambiance = a),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fumeur accepté'),
                value: _fumeur,
                onChanged: (v) => setState(() => _fumeur = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Animaux acceptés'),
                value: _animaux,
                onChanged: (v) => setState(() => _animaux = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Réservé aux femmes'),
                subtitle: const Text(
                    'Seules les passagères (selon le sexe déclaré dans leur profil) pourront réserver'),
                value: _femmes,
                onChanged: (v) => setState(() => _femmes = v),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.35)),
                  ),
                  child: Text(_error!,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppColors.error)),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              PrimaryButton(
                label: 'Publier',
                icon: Icons.add_circle_outline,
                isLoading: _loading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVehicles(ThemeData theme) {
    if (_vehiclesLoading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.sm),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_vehiclesError != null) {
      return Row(
        children: [
          Expanded(
            child: Text(
              _vehiclesError!,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.error),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _vehiclesLoading = true;
                _vehiclesError = null;
              });
              _loadVehicles();
            },
            child: const Text('Réessayer'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_vehicles.isEmpty)
          Text(
            'Aucun véhicule enregistré. Ajoutez celui que vous utilisez pour ce trajet.',
            style: theme.textTheme.bodyMedium,
          )
        else
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final v in _vehicles)
                ChoiceChip(
                  avatar: const Icon(Icons.directions_car_outlined, size: 18),
                  label: Text('${v.marque} ${v.modele} · ${v.couleur}'),
                  selected: _vehicleId == v.id,
                  onSelected: (_) => setState(() => _selectVehicle(v)),
                ),
            ],
          ),
        TextButton.icon(
          onPressed: _addVehicle,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Ajouter un véhicule'),
        ),
      ],
    );
  }
}

/// Read-only field that opens a picker when tapped.
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.errorText,
  });

  final IconData icon;
  final String label;
  final String? value;
  final String? errorText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          errorText: errorText,
        ),
        child: Text(
          value ?? 'Choisir',
          style: value == null
              ? theme.textTheme.bodyLarge
                  ?.copyWith(color: AppColors.textSecondaryStrong)
              : theme.textTheme.bodyLarge,
        ),
      ),
    );
  }
}

/// Small form to register a vehicle. Pops the created [VehicleDto].
class _AddVehicleDialog extends StatefulWidget {
  const _AddVehicleDialog({required this.api});

  final TripApi api;

  @override
  State<_AddVehicleDialog> createState() => _AddVehicleDialogState();
}

class _AddVehicleDialogState extends State<_AddVehicleDialog> {
  final _formKey = GlobalKey<FormState>();
  final _marque = TextEditingController();
  final _modele = TextEditingController();
  final _couleur = TextEditingController();
  int _seats = 3;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _marque.dispose();
    _modele.dispose();
    _couleur.dispose();
    super.dispose();
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Requis' : null;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final vehicle = await widget.api.addVehicle(
        marque: _marque.text.trim(),
        modele: _modele.text.trim(),
        couleur: _couleur.text.trim(),
        nbPlaces: _seats,
      );
      if (mounted) Navigator.pop(context, vehicle);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Une erreur est survenue, veuillez réessayer');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Nouveau véhicule'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _marque,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Marque'),
                validator: _required,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _modele,
                decoration: const InputDecoration(labelText: 'Modèle'),
                validator: _required,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _couleur,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Couleur'),
                validator: _required,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  const Expanded(child: Text('Places passagers')),
                  IconButton(
                    onPressed:
                        _seats > 1 ? () => setState(() => _seats--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$_seats', style: theme.textTheme.titleMedium),
                  IconButton(
                    onPressed: _seats < TripRules.maxSeats
                        ? () => setState(() => _seats++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(_error!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _loading ? null : _save,
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Text('Enregistrer'),
        ),
      ],
    );
  }
}
