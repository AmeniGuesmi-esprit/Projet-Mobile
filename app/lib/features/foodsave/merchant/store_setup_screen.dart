import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/session/session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../data/foodsave_api.dart';
import '../platform/location_service.dart';
import '../widgets/foodsave_ui.dart';

/// Create / edit the merchant's store: name, address, category and its
/// position on an OpenStreetMap map (tap to move the marker, or use GPS).
/// Pops with the saved [StoreDto].
class StoreSetupScreen extends StatefulWidget {
  const StoreSetupScreen({
    super.key,
    required this.session,
    this.initial,
    this.tileLayer,
  });

  final SessionController session;

  /// Pops with the saved StoreDto.
  final StoreDto? initial;

  /// Map tiles. Defaults to OpenStreetMap; tests inject a placeholder so no
  /// network tile is fetched.
  final Widget? tileLayer;

  /// Test hook: replaces the tile layer of every instance (screens pushed
  /// by other screens) so tests never request map tiles.
  @visibleForTesting
  static Widget? debugTileLayerOverride;

  /// Default map centre: Tunis.
  static const LatLng defaultCenter = LatLng(36.8065, 10.1815);

  @override
  State<StoreSetupScreen> createState() => _StoreSetupScreenState();
}

class _StoreSetupScreenState extends State<StoreSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _mapController = MapController();
  late final FoodSaveApi _api = FoodSaveApi(widget.session.api);
  late final TextEditingController _nom =
      TextEditingController(text: widget.initial?.nom ?? '');
  late final TextEditingController _adresse =
      TextEditingController(text: widget.initial?.adresse ?? '');
  late FoodCategory _categorie = widget.initial?.categorie ?? FoodCategory.mixte;

  /// Chosen position (null until the merchant taps the map or uses GPS).
  late LatLng? _point = widget.initial == null
      ? null
      : LatLng(widget.initial!.latitude, widget.initial!.longitude);

  bool _mapReady = false;
  bool _resolvingAddress = false;

  /// Helper under the address field after a position change.
  String? _addressHint;

  /// Ignores stale answers when the marker moves again meanwhile.
  int _addressRequest = 0;
  bool _locating = false;
  bool _saving = false;
  String? _positionError;

  @override
  void dispose() {
    _nom.dispose();
    _adresse.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _setPoint(LatLng p, {bool moveCamera = false}) {
    setState(() {
      _point = p;
      _positionError = null;
    });
    if (moveCamera && _mapReady) {
      _mapController.move(p, 16);
    }
    _fillAddressFrom(p);
  }

  /// The address follows the marker: it is replaced by the address of the
  /// new position (the merchant can still edit it afterwards).
  Future<void> _fillAddressFrom(LatLng p) async {
    final request = ++_addressRequest;
    setState(() {
      _resolvingAddress = true;
      _addressHint = null;
    });
    String? adresse;
    try {
      adresse = await _api.addressAt(p.latitude, p.longitude);
    } catch (_) {
      adresse = null;
    }
    if (!mounted || request != _addressRequest) return;
    setState(() {
      _resolvingAddress = false;
      if (adresse != null) {
        _adresse.text = adresse;
        _addressHint = 'Adresse mise à jour depuis la carte : '
            'complétez-la si besoin (n°, rue).';
      } else {
        _addressHint = 'Adresse introuvable pour cette position : '
            'saisissez-la.';
      }
    });
  }

  static String _issueMessage(LocationIssue issue) => switch (issue) {
        LocationIssue.permissionDenied =>
          'Autorisation de localisation refusée : touchez la carte pour '
              'placer votre commerce.',
        LocationIssue.permissionDeniedForever =>
          'Localisation bloquée : autorisez-la dans les réglages ou touchez '
              'la carte pour placer votre commerce.',
        LocationIssue.serviceDisabled =>
          'La localisation est désactivée : activez-la dans les réglages ou '
              'touchez la carte.',
        LocationIssue.unavailable =>
          'Position introuvable pour le moment : réessayez à l\'extérieur ou '
              'touchez la carte.',
      };

  Future<void> _useMyPosition() async {
    setState(() => _locating = true);
    LocationResult result;
    try {
      result = await FoodSaveLocationService.instance.currentPosition();
    } catch (_) {
      result = const LocationResult(issue: LocationIssue.unavailable);
    }
    if (!mounted) return;
    setState(() => _locating = false);
    final lat = result.latitude;
    final lng = result.longitude;
    if (result.hasPosition && lat != null && lng != null &&
        isValidLatLng(lat, lng)) {
      _setPoint(LatLng(lat, lng), moveCamera: true);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('Position trouvée : ajustez le repère si besoin.')));
      return;
    }
    final issue = result.issue ?? LocationIssue.unavailable;
    final canOpenSettings = issue == LocationIssue.permissionDeniedForever ||
        issue == LocationIssue.serviceDisabled;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(_issueMessage(issue)),
        action: canOpenSettings
            ? SnackBarAction(
                label: 'Réglages',
                onPressed: () =>
                    FoodSaveLocationService.instance.openSettings(issue),
              )
            : null,
      ));
  }

  Future<void> _save() async {
    final formOk = _formKey.currentState!.validate();
    final point = _point;
    if (point == null || !isValidLatLng(point.latitude, point.longitude)) {
      setState(() => _positionError =
          'Placez votre commerce sur la carte ou utilisez votre position.');
    }
    if (!formOk || point == null || _positionError != null) return;

    setState(() => _saving = true);
    try {
      final store = await _api.saveMyStore(
        nom: _nom.text.trim(),
        adresse: _adresse.text.trim(),
        latitude: point.latitude,
        longitude: point.longitude,
        categorie: _categorie,
      );
      if (mounted) Navigator.of(context).pop(store);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showFoodSaveError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final editing = widget.initial != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Modifier le commerce' : 'Configurer le commerce'),
      ),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xxl),
          children: [
            Text(
              'Les clients situés à moins de '
              '${foodSaveNotificationRadiusKm.round()} km de votre commerce '
              'sont prévenus à chaque nouveau panier.',
              style: theme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _nom,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Nom du commerce',
                hintText: 'Ex. : Boulangerie du Lac',
                prefixIcon: Icon(Icons.storefront_outlined),
              ),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.length < 2) {
                  return 'Saisissez le nom du commerce (2 caractères minimum).';
                }
                if (t.length > 80) return '80 caractères maximum.';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _adresse,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              maxLength: 200,
              decoration: InputDecoration(
                labelText: 'Adresse',
                hintText: 'Ex. : 12 rue du Lac Léman, Tunis',
                prefixIcon: const Icon(Icons.place_outlined),
                helperText: _addressHint,
                helperMaxLines: 2,
                suffixIcon: _resolvingAddress
                    ? const Padding(
                        padding: EdgeInsets.all(AppSpacing.sm),
                        child: SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
              ),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.length < 5) {
                  return 'Saisissez l\'adresse complète du commerce.';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<FoodCategory>(
              initialValue: _categorie,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Catégorie',
                prefixIcon: Icon(FoodCategoryMeta.icon(_categorie)),
              ),
              items: [
                for (final c in FoodCategory.values)
                  DropdownMenuItem(
                    value: c,
                    child: Row(
                      children: [
                        Icon(FoodCategoryMeta.icon(c),
                            size: 20, color: AppColors.moduleFoodSaveDeep),
                        const SizedBox(width: AppSpacing.sm),
                        Flexible(
                            child: Text(c.label,
                                overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (c) {
                      if (c != null) setState(() => _categorie = c);
                    },
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Position du commerce', style: theme.titleMedium),
            const SizedBox(height: AppSpacing.xxs),
            Text(
                'Touchez la carte pour placer le repère sur votre vitrine : '
                'l\'adresse se met à jour automatiquement.',
                style: theme.bodySmall),
            const SizedBox(height: AppSpacing.sm),
            _mapCard(),
            AnimatedSwitcher(
              duration: FoodSaveMotion.fast,
              child: _positionError == null
                  ? _coordinates(theme)
                  : Padding(
                      key: const ValueKey('position-error'),
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(_positionError!,
                          style: theme.bodySmall
                              ?.copyWith(color: AppColors.error)),
                    ),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.moduleFoodSaveDeep,
                side: const BorderSide(
                    color: AppColors.moduleFoodSaveDeep, width: 1.4),
              ),
              onPressed: _locating || _saving ? null : _useMyPosition,
              icon: _locating
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
              label: Text(_locating
                  ? 'Localisation en cours…'
                  : 'Utiliser ma position'),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              style: foodSaveFilledStyle(),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white))
                  : Text(editing
                      ? 'Enregistrer les modifications'
                      : 'Enregistrer mon commerce'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coordinates(TextTheme theme) {
    final p = _point;
    return Padding(
      key: ValueKey(p == null ? 'no-point' : 'point'),
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(
        p == null
            ? 'Aucune position choisie pour le moment.'
            : 'Position : ${_fmtCoord(p.latitude)}, ${_fmtCoord(p.longitude)}',
        style: theme.bodySmall,
      ),
    );
  }

  static String _fmtCoord(double v) =>
      v.toStringAsFixed(5).replaceAll('.', ',');

  Widget _mapCard() {
    final p = _point;
    return Semantics(
      label: p == null
          ? 'Carte : touchez pour placer votre commerce'
          : 'Carte : repère placé, touchez pour le déplacer',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          height: 260,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.outlineSoft),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: p ?? StoreSetupScreen.defaultCenter,
              initialZoom: p == null ? 13 : 16,
              backgroundColor: AppColors.outlineSoft,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onMapReady: () => _mapReady = true,
              onTap: _saving ? null : (_, point) => _setPoint(point),
            ),
            children: [
              widget.tileLayer ??
                  StoreSetupScreen.debugTileLayerOverride ??
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.proxilife.app',
                  ),
              if (p != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: p,
                      width: 48,
                      height: 48,
                      alignment: Alignment.topCenter,
                      child: const Icon(Icons.location_on,
                          size: 48, color: AppColors.moduleFoodSaveDeep),
                    ),
                  ],
                ),
              const _OsmAttribution(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Required OpenStreetMap attribution, bottom-right of the map.
class _OsmAttribution extends StatelessWidget {
  const _OsmAttribution();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.xxs),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(AppSpacing.xxs),
        ),
        child: const Text('© OpenStreetMap',
            style: TextStyle(fontSize: 11, color: AppColors.text)),
      ),
    );
  }
}
