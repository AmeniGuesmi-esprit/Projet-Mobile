import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../data/geolocator_location_provider.dart';
import '../../../data/url_launcher_link_opener.dart';
import '../../../domain/teledoc_call.dart';
import '../../../domain/teledoc_formatters.dart';
import '../../../domain/teledoc_location.dart';
import '../../../domain/teledoc_repository.dart';
import '../../widgets/teledoc_async_view.dart';

/// Position used for the search + the on-duty pharmacies around it.
class _PharmacySearch {
  const _PharmacySearch(this.position, this.issue, this.pharmacies);

  final TeledocPosition position;

  /// Set when the GPS failed and [position] is the Tunis fallback.
  final TeledocLocationIssue? issue;
  final List<TeledocPharmacyDto> pharmacies;
}

/// Nearest on-duty pharmacies: OpenStreetMap map + list sorted by distance
/// (computed by the server, Haversine), itinerary and phone call.
///
/// With a [consultationId] (finished consultation), the patient can also
/// send the prescription to the chosen pharmacy; the screen then pops with
/// the updated consultation.
class TeledocPharmacyScreen extends StatefulWidget {
  const TeledocPharmacyScreen({
    super.key,
    required this.repository,
    this.consultationId,
    this.selectedPharmacyId,
    this.location = const GeolocatorLocationProvider(),
    this.linkOpener = const UrlLauncherLinkOpener(),
    this.showMap = true,
  });

  final TeledocRepository repository;
  final int? consultationId;
  final int? selectedPharmacyId;
  final TeledocLocationProvider location;
  final TeledocLinkOpener linkOpener;

  /// Widget tests turn the map off (no network tiles in tests).
  final bool showMap;

  @override
  State<TeledocPharmacyScreen> createState() => _TeledocPharmacyScreenState();
}

class _TeledocPharmacyScreenState extends State<TeledocPharmacyScreen> {
  static const int _limit = 8;

  final _mapController = MapController();
  late Future<_PharmacySearch> _future;
  int? _highlighted;
  int? _sendingTo;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<_PharmacySearch> _load() async {
    TeledocPosition position;
    TeledocLocationIssue? issue;
    try {
      position = await widget.location.current();
    } on TeledocLocationException catch (e) {
      position = teledocTunisCentre;
      issue = e.issue;
    }
    final pharmacies = await widget.repository.nearestPharmacies(
      lat: position.latitude,
      lng: position.longitude,
      limit: _limit,
    );
    return _PharmacySearch(position, issue, pharmacies);
  }

  void _reload() {
    setState(() {
      _highlighted = null;
      _future = _load();
    });
  }

  void _highlight(TeledocPharmacyDto pharmacy) {
    setState(() => _highlighted = pharmacy.id);
    if (widget.showMap) {
      _mapController.move(LatLng(pharmacy.latitude, pharmacy.longitude), 15);
    }
  }

  Future<void> _directions(
    TeledocPosition from,
    TeledocPharmacyDto pharmacy,
  ) async {
    final opened =
        await widget.linkOpener.open(TeledocPharmacyLinks.mapsApp(pharmacy)) ||
        await widget.linkOpener.open(
          TeledocPharmacyLinks.webDirections(from, pharmacy),
        );
    if (!opened && mounted) {
      showTeledocSnack(context, 'Aucune application de cartes disponible');
    }
  }

  Future<void> _call(TeledocPharmacyDto pharmacy) async {
    final opened = await widget.linkOpener.open(
      TeledocPharmacyLinks.phone(pharmacy.telephone),
    );
    if (!opened && mounted) {
      showTeledocSnack(context, 'Appelez le ${pharmacy.telephone}');
    }
  }

  Future<void> _send(TeledocPharmacyDto pharmacy) async {
    final consultationId = widget.consultationId!;
    setState(() => _sendingTo = pharmacy.id);
    try {
      final updated = await widget.repository.choosePharmacy(
        consultationId,
        pharmacy.id,
      );
      if (!mounted) return;
      showTeledocSnack(context, 'Ordonnance envoyée à ${pharmacy.nom}');
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (mounted) showTeledocSnack(context, teledocErrorMessage(e));
    } finally {
      if (mounted) setState(() => _sendingTo = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pharmacies de garde'),
        actions: [
          IconButton(
            tooltip: 'Actualiser ma position',
            onPressed: _reload,
            icon: const Icon(Icons.my_location),
          ),
        ],
      ),
      body: TeledocAsyncView<_PharmacySearch>(
        future: _future,
        onRetry: _reload,
        builder: (context, search) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (search.issue != null) _approximateBanner(context, search),
            if (widget.showMap && search.pharmacies.isNotEmpty)
              SizedBox(height: 220, child: _map(search)),
            Expanded(child: _list(context, search)),
          ],
        ),
      ),
    );
  }

  Widget _approximateBanner(BuildContext context, _PharmacySearch search) {
    final issue = search.issue!;
    final canFix = issue != TeledocLocationIssue.unavailable;
    return Material(
      color: AppColors.warning.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            const Icon(Icons.location_off_outlined, size: 20),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                '${issue.message} Distances calculées depuis Tunis centre.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            TextButton(
              onPressed: canFix
                  ? () => widget.location.openSettings(issue)
                  : _reload,
              child: Text(canFix ? 'Réglages' : 'Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _map(_PharmacySearch search) {
    final me = LatLng(search.position.latitude, search.position.longitude);
    final points = [
      for (final p in search.pharmacies) LatLng(p.latitude, p.longitude),
    ];
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCameraFit: CameraFit.coordinates(
          coordinates: [me, ...points],
          padding: const EdgeInsets.all(32),
          maxZoom: 15,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          // Required by the OpenStreetMap tile usage policy.
          userAgentPackageName: 'com.proxilife.app',
        ),
        MarkerLayer(
          markers: [
            for (final (i, p) in search.pharmacies.indexed)
              Marker(
                point: points[i],
                width: 36,
                height: 36,
                child: _MapPin(
                  number: i + 1,
                  name: p.nom,
                  highlighted: p.id == _highlighted,
                  onTap: () => _highlight(p),
                ),
              ),
            // Drawn last: always visible above the pharmacy pins.
            Marker(
              point: me,
              width: 22,
              height: 22,
              child: Semantics(
                label: 'Ma position',
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.info,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
            ),
          ],
        ),
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution(
              'OpenStreetMap contributors',
              onTap: () => widget.linkOpener.open(
                Uri.https('www.openstreetmap.org', '/copyright'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _list(BuildContext context, _PharmacySearch search) {
    if (search.pharmacies.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          Text(
            'Aucune pharmacie de garde trouvée pour le moment.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: search.pharmacies.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, i) {
        final p = search.pharmacies[i];
        return _PharmacyCard(
          number: i + 1,
          pharmacy: p,
          highlighted: p.id == _highlighted,
          chosen: p.id == widget.selectedPharmacyId,
          canSend: widget.consultationId != null,
          sending: _sendingTo == p.id,
          busy: _sendingTo != null,
          onTap: () => _highlight(p),
          onDirections: () => _directions(search.position, p),
          onCall: () => _call(p),
          onSend: () => _send(p),
        );
      },
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({
    required this.number,
    required this.name,
    required this.highlighted,
    required this.onTap,
  });

  final int number;
  final String name;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = highlighted ? AppColors.primary : AppColors.moduleTeleDoc;
    return Semantics(
      button: true,
      label: '$number. $name',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
          ),
          child: Text(
            '$number',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _PharmacyCard extends StatelessWidget {
  const _PharmacyCard({
    required this.number,
    required this.pharmacy,
    required this.highlighted,
    required this.chosen,
    required this.canSend,
    required this.sending,
    required this.busy,
    required this.onTap,
    required this.onDirections,
    required this.onCall,
    required this.onSend,
  });

  final int number;
  final TeledocPharmacyDto pharmacy;
  final bool highlighted;
  final bool chosen;
  final bool canSend;
  final bool sending;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onDirections;
  final VoidCallback onCall;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      shape: highlighted
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: const BorderSide(color: AppColors.primary, width: 2),
            )
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.moduleTeleDoc,
                    child: Text(
                      '$number',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pharmacy.nom, style: theme.textTheme.titleMedium),
                        Text(
                          pharmacy.adresse,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    teledocDistance(pharmacy.distanceKm),
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  TextButton.icon(
                    onPressed: onDirections,
                    icon: const Icon(Icons.directions, size: 18),
                    label: const Text('Itinéraire'),
                  ),
                  TextButton.icon(
                    onPressed: onCall,
                    icon: const Icon(Icons.call_outlined, size: 18),
                    label: const Text('Appeler'),
                  ),
                ],
              ),
              if (canSend)
                chosen
                    ? const Chip(
                        avatar: Icon(Icons.check, size: 18),
                        label: Text('Ordonnance envoyée ici'),
                      )
                    : FilledButton.icon(
                        onPressed: busy ? null : onSend,
                        icon: sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_outlined),
                        label: const Text('Envoyer mon ordonnance ici'),
                      ),
            ],
          ),
        ),
      ),
    );
  }
}
