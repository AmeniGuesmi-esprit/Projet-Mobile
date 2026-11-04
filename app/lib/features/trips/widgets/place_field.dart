import 'package:flutter/material.dart';

import '../../../core/location/device_location_service.dart';
import '../../../core/location/geocoding_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

/// Address field that resolves to GPS coordinates.
///
/// The user either types an address and taps the search icon, or (when
/// [allowCurrentLocation] is true) taps "Utiliser ma position actuelle".
/// [value] is `null` until a place has been chosen; editing the text after a
/// choice resets it to `null`.
class PlaceField extends StatefulWidget {
  const PlaceField({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    required this.onChanged,
    required this.geocoder,
    this.locationService = const DeviceLocationService(),
    this.allowCurrentLocation = false,
    this.errorText,
  });

  final String label;
  final IconData icon;
  final GeoPlace? value;
  final ValueChanged<GeoPlace?> onChanged;
  final GeocodingService geocoder;
  final DeviceLocationService locationService;
  final bool allowCurrentLocation;
  final String? errorText;

  @override
  State<PlaceField> createState() => _PlaceFieldState();
}

class _PlaceFieldState extends State<PlaceField> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    final value = widget.value;
    if (value != null) _controller.text = value.label;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _select(GeoPlace place) {
    _controller.text = place.label;
    setState(() => _message = null);
    widget.onChanged(place);
  }

  void _onTextChanged(String text) {
    final current = widget.value;
    if (current != null && text != current.label) widget.onChanged(null);
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.length < 3) {
      setState(() => _message = 'Saisissez au moins 3 caractères');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final results = await widget.geocoder.search(query);
      if (!mounted) return;
      if (results.isEmpty) {
        setState(() => _message = 'Aucune adresse trouvée');
      } else if (results.length == 1) {
        _select(results.first);
      } else {
        final picked = await showModalBottomSheet<GeoPlace>(
          context: context,
          builder: (_) => _ResultsSheet(results: results),
        );
        if (picked != null) _select(picked);
      }
    } on GeocodingException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useCurrentLocation() async {
    final service = widget.locationService;
    try {
      if (await service.needsPermissionPrompt()) {
        if (!mounted) return;
        final consent = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.my_location, color: AppColors.primary),
            title: const Text('Utiliser votre position ?'),
            content: const Text(
              'ProxiLife utilise votre position uniquement pour renseigner '
              'l\'adresse de départ de votre trajet. Elle n\'est pas '
              'enregistrée en continu.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Non merci'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Autoriser'),
              ),
            ],
          ),
        );
        if (consent != true) return;
        await service.requestPermission();
      }
      if (!mounted) return;
      setState(() {
        _busy = true;
        _message = null;
      });
      final position = await service.currentPosition();
      final place = await widget.geocoder
          .reverse(position.latitude, position.longitude);
      if (!mounted) return;
      _select(place ??
          GeoPlace(
            label: 'Ma position actuelle',
            latitude: position.latitude,
            longitude: position.longitude,
          ));
    } on LocationException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          onChanged: _onTextChanged,
          decoration: InputDecoration(
            labelText: widget.label,
            prefixIcon: Icon(widget.icon),
            errorText: widget.errorText,
            helperText: widget.value != null
                ? 'Position enregistrée ✓'
                : 'Tapez une adresse puis appuyez sur la loupe',
            suffixIcon: _busy
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.sm),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: 'Rechercher cette adresse',
                    onPressed: _search,
                  ),
          ),
        ),
        if (widget.allowCurrentLocation)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : _useCurrentLocation,
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text('Utiliser ma position actuelle'),
            ),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Text(
              _message!,
              style:
                  theme.textTheme.bodySmall?.copyWith(color: AppColors.error),
            ),
          ),
      ],
    );
  }
}

class _ResultsSheet extends StatelessWidget {
  const _ResultsSheet({required this.results});

  final List<GeoPlace> results;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(
              'Choisissez l\'adresse exacte',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final place in results)
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(place.label),
              onTap: () => Navigator.pop(context, place),
            ),
        ],
      ),
    );
  }
}
