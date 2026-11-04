import 'package:flutter/material.dart';

import '../../core/location/geocoding_service.dart';
import '../../core/session/session_controller.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/primary_button.dart';
import '../trips/trip_labels.dart';
import '../trips/widgets/place_field.dart';
import 'trip_results_screen.dart';
import 'trip_search_query.dart';

/// "Où allez-vous ?" (passenger): position, destination, date, radius and
/// travel preferences. Opens the results screen.
class SearchTripsScreen extends StatefulWidget {
  const SearchTripsScreen({super.key, required this.session, this.embedded = false});

  final SessionController session;

  /// Shown inside [CovoiturageHubScreen] (no own app bar).
  final bool embedded;

  @override
  State<SearchTripsScreen> createState() => _SearchTripsScreenState();
}

class _SearchTripsScreenState extends State<SearchTripsScreen> {
  final _geocoder = GeocodingService();

  GeoPlace? _depart;
  GeoPlace? _arrivee;
  DateTime? _date;
  TimeOfDay? _heure;
  double _rayon = 5;
  int _places = 1;
  bool _silence = false;
  bool _nonFumeur = false;
  bool _animaux = false;
  bool _femmes = false;
  bool _submitted = false;

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
      initialTime: _heure ?? TimeOfDay.now(),
      helpText: 'Heure de départ souhaitée',
      cancelText: 'Annuler',
      confirmText: 'OK',
    );
    if (picked != null) setState(() => _heure = picked);
  }

  DateTime? get _heureComplete {
    final t = _heure;
    if (t == null) return null;
    final day = _date ?? DateTime.now();
    return DateTime(day.year, day.month, day.day, t.hour, t.minute);
  }

  void _search() {
    setState(() => _submitted = true);
    final depart = _depart;
    if (depart == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TripResultsScreen(
          session: widget.session,
          query: TripSearchQuery(
            depart: depart,
            arrivee: _arrivee,
            rayonKm: _rayon,
            date: _date,
            heure: _heureComplete,
            places: _places,
            silence: _silence,
            nonFumeur: _nonFumeur,
            animaux: _animaux,
            femmes: _femmes,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      // Inside the "Covoiturage" hub, its tab bar replaces this one.
      appBar: widget.embedded
          ? null
          : AppBar(
              automaticallyImplyLeading: false,
              title: const Text('Rechercher un trajet'),
            ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            PlaceField(
              label: 'Où êtes-vous ?',
              icon: Icons.trip_origin,
              value: _depart,
              geocoder: _geocoder,
              allowCurrentLocation: true,
              errorText: _submitted && _depart == null
                  ? 'Choisissez votre position (loupe ou « ma position »)'
                  : null,
              onChanged: (p) => setState(() => _depart = p),
            ),
            const SizedBox(height: AppSpacing.md),
            PlaceField(
              label: 'Destination (facultative, validez avec la loupe)',
              icon: Icons.flag_outlined,
              value: _arrivee,
              geocoder: _geocoder,
              onChanged: (p) => setState(() => _arrivee = p),
            ),
            const SizedBox(height: AppSpacing.md),
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: _pickDate,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Date',
                  prefixIcon: const Icon(Icons.calendar_today_outlined),
                  suffixIcon: _date == null
                      ? null
                      : IconButton(
                          tooltip: 'Toutes les dates',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _date = null),
                        ),
                ),
                child: Text(
                  _date == null ? 'Toutes les dates' : formatTripDate(_date!),
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: _pickTime,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Heure souhaitée (± 1 h)',
                  prefixIcon: const Icon(Icons.schedule),
                  suffixIcon: _heure == null
                      ? null
                      : IconButton(
                          tooltip: 'Toute heure',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _heure = null),
                        ),
                ),
                child: Text(
                  _heure == null ? 'Toute heure' : _heure!.format(context),
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Rayon : ${_rayon.round()} km',
                style: theme.textTheme.titleMedium),
            Slider(
              value: _rayon,
              min: 2,
              max: 10,
              divisions: 8,
              label: '${_rayon.round()} km',
              onChanged: (v) => setState(() => _rayon = v),
            ),
            Row(
              children: [
                Expanded(
                  child: Text('Places souhaitées',
                      style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: 'Moins',
                  onPressed:
                      _places > 1 ? () => setState(() => _places--) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$_places', style: theme.textTheme.titleLarge),
                IconButton(
                  tooltip: 'Plus',
                  onPressed:
                      _places < 4 ? () => setState(() => _places++) : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Préférences de voyage', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                FilterChip(
                  label: const Text('Silence'),
                  selected: _silence,
                  onSelected: (v) => setState(() => _silence = v),
                ),
                FilterChip(
                  label: const Text('Non-fumeur'),
                  selected: _nonFumeur,
                  onSelected: (v) => setState(() => _nonFumeur = v),
                ),
                FilterChip(
                  label: const Text('Animaux'),
                  selected: _animaux,
                  onSelected: (v) => setState(() => _animaux = v),
                ),
                FilterChip(
                  label: const Text('Femmes'),
                  selected: _femmes,
                  onSelected: (v) => setState(() => _femmes = v),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Rechercher',
              icon: Icons.search,
              onPressed: _search,
            ),
          ],
        ),
      ),
    );
  }
}
