import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/location/geocoding_service.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/primary_button.dart';
import '../../../trips/widgets/place_field.dart';
import '../../data/coach_api.dart';
import '../widgets/coach_format.dart';
import '../widgets/coach_widgets.dart';

/// Coach: publish a new session, or edit one that has not started yet
/// (pass [existing]). Pops `true` once saved.
class CoachSessionFormScreen extends StatefulWidget {
  const CoachSessionFormScreen({
    super.key,
    required this.session,
    this.existing,
  });

  final SessionController session;
  final CoachSessionDto? existing;

  @override
  State<CoachSessionFormScreen> createState() => _CoachSessionFormScreenState();
}

/// 1500 -> "15", 1250 -> "12.50".
String _priceText(int cents) => cents % 100 == 0
    ? '${cents ~/ 100}'
    : (cents / 100).toStringAsFixed(2);

class _CoachSessionFormScreenState extends State<CoachSessionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final GeocodingService _geocoder = GeocodingService();
  late final CoachApi _api = CoachApi(widget.session.api);

  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _duration;
  late final TextEditingController _places;
  late final TextEditingController _price;

  late CoachSessionType _type;
  late CoachLevel _level;
  GeoPlace? _place;
  DateTime? _start;

  bool _saving = false;
  String? _placeError;
  String? _startError;
  String? _error;

  CoachSessionDto? get _existing => widget.existing;

  /// The server refuses to change the price once someone has booked.
  bool get _priceLocked => (_existing?.inscrits ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    final e = _existing;
    _title = TextEditingController(text: e?.titre ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _duration = TextEditingController(text: '${e?.dureeMinutes ?? 60}');
    _places = TextEditingController(text: '${e?.placesTotales ?? 10}');
    _price = TextEditingController(
        text: e == null ? '0' : _priceText(e.prixCentimes));
    _type = e?.type ?? CoachSessionType.fitness;
    _level = e?.niveau ?? CoachLevel.debutant;
    if (e != null) {
      _place = GeoPlace(
          label: e.lieu, latitude: e.latitude, longitude: e.longitude);
      _start = e.dateHeure.toLocal();
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _duration.dispose();
    _places.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    var initial = _start ?? now.add(const Duration(days: 1));
    if (initial.isBefore(now)) initial = now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    setState(() {
      _start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _startError = null;
    });
  }

  String? _required(String? v, String message) =>
      (v == null || v.trim().isEmpty) ? message : null;

  Future<void> _submit() async {
    final formOk = _formKey.currentState?.validate() ?? false;
    setState(() {
      _placeError =
          _place == null ? 'Recherchez et choisissez l\'adresse du lieu' : null;
      _startError = _start == null ? 'Choisissez la date et l\'heure' : null;
      _error = null;
    });
    final place = _place;
    final start = _start;
    if (!formOk || place == null || start == null) return;

    final duration = int.tryParse(_duration.text.trim()) ?? 0;
    final places = int.tryParse(_places.text.trim()) ?? 0;
    final cents = parseDinarsToCents(_price.text);
    if (cents == null) {
      setState(() => _error = 'Prix invalide (exemple : 15 ou 12,5)');
      return;
    }
    final description = _description.text.trim();
    final problem = CoachRules.validateSession(
      titre: _title.text,
      description: description,
      lieu: place.label,
      latitude: place.latitude,
      longitude: place.longitude,
      dateHeure: start,
      dureeMinutes: duration,
      places: places,
      prixCentimes: cents,
      now: DateTime.now(),
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    final form = CoachSessionForm(
      titre: _title.text.trim(),
      description: description.isEmpty ? null : description,
      type: _type,
      niveau: _level,
      lieu: place.label,
      latitude: place.latitude,
      longitude: place.longitude,
      dateHeure: start,
      dureeMinutes: duration,
      places: places,
      prixCentimes: cents,
    );
    setState(() => _saving = true);
    try {
      final existing = _existing;
      if (existing == null) {
        await _api.publish(form);
      } else {
        await _api.update(existing.id, form);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
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
    final editing = _existing != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Modifier la séance' : 'Publier une séance'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              maxLength: CoachRules.maxTitleLength,
              decoration: const InputDecoration(
                labelText: 'Titre de la séance',
                hintText: 'Ex. Yoga au lever du soleil',
                prefixIcon: Icon(Icons.title),
              ),
              validator: (v) => _required(v, 'Donnez un titre à la séance'),
            ),
            const CoachSectionTitle('Sport'),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final t in CoachSessionType.values)
                  ChoiceChip(
                    avatar: Icon(coachTypeIcon(t), size: 18),
                    label: Text(t.label),
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                  ),
              ],
            ),
            const CoachSectionTitle('Niveau'),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final l in CoachLevel.values)
                  ChoiceChip(
                    label: Text(l.label),
                    selected: _level == l,
                    onSelected: (_) => setState(() => _level = l),
                  ),
              ],
            ),
            const CoachSectionTitle('Lieu'),
            PlaceField(
              label: 'Adresse de la séance',
              icon: Icons.place_outlined,
              value: _place,
              geocoder: _geocoder,
              errorText: _placeError,
              onChanged: (p) => setState(() {
                _place = p;
                _placeError = null;
              }),
            ),
            const CoachSectionTitle('Date et heure'),
            OutlinedButton.icon(
              onPressed: _pickStart,
              icon: const Icon(Icons.event_outlined),
              label: Text(_start == null
                  ? 'Choisir la date et l\'heure'
                  : '${coachDay(_start!)} à ${coachClock(_start!)}'),
            ),
            if (_startError != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(_startError!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.error)),
              ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _duration,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Durée',
                      suffixText: 'min',
                      prefixIcon: Icon(Icons.timer_outlined),
                    ),
                    validator: (v) => _required(v, 'Durée requise'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextFormField(
                    controller: _places,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Places',
                      prefixIcon: Icon(Icons.group_outlined),
                    ),
                    validator: (v) => _required(v, 'Places requises'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _price,
              enabled: !_priceLocked,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText: 'Prix par participant',
                suffixText: 'DT',
                prefixIcon: const Icon(Icons.payments_outlined),
                helperText: _priceLocked
                    ? 'Le prix ne peut plus changer : des clients ont réservé'
                    : '0 = séance gratuite',
              ),
              validator: (v) => _required(v, 'Indiquez le prix (0 si gratuit)'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _description,
              maxLines: 4,
              maxLength: CoachRules.maxDescriptionLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description (facultatif)',
                alignLabelWithHint: true,
                hintText: 'Matériel à apporter, programme, point de rendez-vous…',
              ),
            ),
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(top: AppSpacing.sm),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border:
                      Border.all(color: AppColors.error.withValues(alpha: 0.35)),
                ),
                child: Text(_error!,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppColors.error)),
              ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: editing ? 'Enregistrer les modifications' : 'Publier la séance',
              icon: Icons.check,
              isLoading: _saving,
              onPressed: _submit,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}
