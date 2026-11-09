import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/session/session_controller.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/money_text.dart';
import '../../core/widgets/primary_button.dart';
import '../reservations/reservation_api.dart' show apiErrorMessage;
import 'service_now_api.dart';
import 'service_now_format.dart';
import 'widgets/service_now_widgets.dart';

/// Creates a request, or edits [initial] while it is still waiting.
/// Pops with `true` once saved.
class DemandeFormScreen extends StatefulWidget {
  const DemandeFormScreen({super.key, required this.session, this.initial});

  final SessionController session;
  final DemandeServiceDto? initial;

  @override
  State<DemandeFormScreen> createState() => _DemandeFormScreenState();
}

class _DemandeFormScreenState extends State<DemandeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final ServiceNowApi _api = ServiceNowApi(widget.session.api);
  late final TextEditingController _description =
      TextEditingController(text: widget.initial?.description);
  late final TextEditingController _adresse =
      TextEditingController(text: widget.initial?.adresse);
  late ServiceNowType _type = widget.initial?.type ?? ServiceNowType.plomberie;
  late DateTime? _date = widget.initial?.dateSouhaitee.toLocal();
  String? _dateError;
  bool _saving = false;
  bool _locating = false;

  /// Coordinates are only valid for the exact text they were found for.
  late String? _locatedAddress =
      widget.initial?.latitude == null ? null : widget.initial?.adresse;
  late double? _latitude = widget.initial?.latitude;
  late double? _longitude = widget.initial?.longitude;
  late Future<PriceEstimateDto> _estimate = _api.estimate(_type);

  bool get _isLocated =>
      _locatedAddress != null && _locatedAddress == _adresse.text.trim();

  bool get _editing => widget.initial != null;

  @override
  void dispose() {
    _description.dispose();
    _adresse.dispose();
    super.dispose();
  }

  String? _validateDate() {
    final date = _date;
    if (date == null) return 'Choisissez une date';
    return ServiceNowRules.scheduleError(date, now: DateTime.now());
  }

  void _selectType(ServiceNowType type) {
    setState(() {
      _type = type;
      _estimate = _api.estimate(type);
    });
  }

  /// Looks the typed address up on the map; asks which one if several match.
  Future<void> _locate() async {
    final query = _adresse.text.trim();
    if (ServiceNowRules.addressError(query) != null) return;
    FocusScope.of(context).unfocus();
    setState(() => _locating = true);
    try {
      final results = await _api.searchAddress(query);
      if (!mounted) return;
      if (results.isEmpty) {
        _snack('Adresse introuvable : précisez la ville');
        return;
      }
      final chosen = results.length == 1
          ? results.first
          : await showModalBottomSheet<GeocodeResultDto>(
              context: context,
              showDragHandle: true,
              builder: (sheetContext) => SafeArea(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final result in results)
                      ListTile(
                        leading: const Icon(Icons.place_outlined),
                        title: Text(result.label),
                        onTap: () => Navigator.pop(sheetContext, result),
                      ),
                  ],
                ),
              ),
            );
      if (chosen == null || !mounted) return;
      setState(() {
        _adresse.text = chosen.label;
        _locatedAddress = chosen.label.trim();
        _latitude = chosen.latitude;
        _longitude = chosen.longitude;
      });
    } catch (e) {
      if (mounted) _snack(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _submit() async {
    final formValid = _formKey.currentState!.validate();
    final dateError = _validateDate();
    setState(() => _dateError = dateError);
    if (!formValid || dateError != null) return;

    setState(() => _saving = true);
    try {
      final initial = widget.initial;
      final latitude = _isLocated ? _latitude : null;
      final longitude = _isLocated ? _longitude : null;
      if (initial == null) {
        await _api.create(
          type: _type,
          description: _description.text.trim(),
          adresse: _adresse.text.trim(),
          dateSouhaitee: _date!,
          latitude: latitude,
          longitude: longitude,
        );
      } else {
        await _api.update(
          initial.id,
          type: _type,
          description: _description.text.trim(),
          adresse: _adresse.text.trim(),
          dateSouhaitee: _date!,
          latitude: latitude,
          longitude: longitude,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Modifier la demande' : 'Nouvelle demande'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text('Type de service', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final type in ServiceNowType.values)
                    ChoiceChip(
                      avatar: Icon(serviceTypeIcon(type), size: 18),
                      showCheckmark: false,
                      label: Text(type.label),
                      selected: _type == type,
                      onSelected: (_) => _selectType(type),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              FutureBuilder<PriceEstimateDto>(
                future: _estimate,
                builder: (context, snapshot) {
                  final estimate = snapshot.data;
                  if (estimate == null) return const SizedBox.shrink();
                  return InfoLine(
                    icon: Icons.sell_outlined,
                    text: 'Prix estimé : '
                        '${MoneyText.format(estimate.minCentimes)} à '
                        '${MoneyText.format(estimate.maxCentimes)}',
                  );
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _description,
                keyboardType: TextInputType.multiline,
                minLines: 3,
                maxLines: 6,
                maxLength: ServiceNowRules.maxDescriptionLength,
                decoration: const InputDecoration(
                  labelText: 'Description du besoin',
                  alignLabelWithHint: true,
                ),
                validator: (value) =>
                    ServiceNowRules.descriptionError(value ?? ''),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _adresse,
                textInputAction: TextInputAction.done,
                maxLength: ServiceNowRules.maxAddressLength,
                decoration: const InputDecoration(
                  labelText: 'Adresse d\'intervention',
                ),
                onChanged: (_) => setState(() {}),
                validator: (value) => ServiceNowRules.addressError(value ?? ''),
              ),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _locating ? null : _locate,
                  icon: Icon(_isLocated ? Icons.check_circle : Icons.search),
                  label: Text(_isLocated
                      ? 'Adresse localisée'
                      : _locating
                          ? 'Recherche...'
                          : 'Localiser sur la carte'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              DateTimeField(
                label: 'Date souhaitée',
                value: _date,
                errorText: _dateError,
                onChanged: (value) => setState(() {
                  _date = value;
                  _dateError = _validateDate();
                }),
              ),
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: _editing ? 'Enregistrer' : 'Envoyer la demande',
                isLoading: _saving,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
