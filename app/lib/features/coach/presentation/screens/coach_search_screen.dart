import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/location/device_location_service.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../data/coach_api.dart';
import '../coach_theme.dart';
import '../widgets/coach_format.dart';
import '../widgets/coach_widgets.dart';
import 'coach_session_detail_screen.dart';

/// Client: search the upcoming sessions (type, lieu, date, niveau, prix) and
/// sort them by distance from the phone's GPS position.
class CoachSearchScreen extends StatefulWidget {
  const CoachSearchScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<CoachSearchScreen> createState() => _CoachSearchScreenState();
}

/// 1500 -> "15", 1250 -> "12.50", null -> "".
String _priceText(int? cents) {
  if (cents == null) return '';
  if (cents % 100 == 0) return '${cents ~/ 100}';
  return (cents / 100).toStringAsFixed(2);
}

class _CoachSearchScreenState extends State<CoachSearchScreen> {
  late final CoachApi _api = CoachApi(widget.session.api);
  final TextEditingController _placeController = TextEditingController();

  CoachSessionType? _type;
  CoachLevel? _level;
  DateTime? _day;
  int? _maxPriceCents;
  bool _nearMe = false;
  ({double latitude, double longitude})? _position;

  late Future<List<CoachSessionDto>> _future = _load();

  @override
  void dispose() {
    _placeController.dispose();
    super.dispose();
  }

  int get _activeFilters =>
      (_level != null ? 1 : 0) +
      (_day != null ? 1 : 0) +
      (_maxPriceCents != null ? 1 : 0);

  Future<List<CoachSessionDto>> _load() {
    final day = _day;
    final position = _nearMe ? _position : null;
    return _api.search(
      type: _type,
      niveau: _level,
      lieu: _placeController.text,
      from: day == null ? null : DateTime(day.year, day.month, day.day),
      to: day == null ? null : DateTime(day.year, day.month, day.day + 1),
      prixMaxCentimes: _maxPriceCents,
      latitude: position?.latitude,
      longitude: position?.longitude,
      sortByDistance: position != null,
    );
  }

  void _reload() => setState(() {
        _future = _load();
      });

  void _resetFilters() {
    _placeController.clear();
    setState(() {
      _type = null;
      _level = null;
      _day = null;
      _maxPriceCents = null;
      _future = _load();
    });
  }

  Future<void> _toggleNearMe() async {
    if (_nearMe) {
      setState(() {
        _nearMe = false;
        _position = null;
        _future = _load();
      });
      return;
    }
    const service = DeviceLocationService();
    try {
      if (await service.needsPermissionPrompt()) {
        if (!mounted) return;
        final consent = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.my_location, color: CoachColors.brandDeep),
            title: const Text('Utiliser votre position ?'),
            content: const Text(
              'CoachProche utilise votre position pour afficher les séances '
              'les plus proches et la distance jusqu\'au lieu. Elle n\'est '
              'pas enregistrée.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Non merci'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Autoriser'),
              ),
            ],
          ),
        );
        if (consent != true) return;
        await service.requestPermission();
      }
      final position = await service.currentPosition();
      if (!mounted) return;
      setState(() {
        _nearMe = true;
        _position = position;
        _future = _load();
      });
    } on LocationException catch (e) {
      if (mounted) showCoachSnack(context, e.message);
    }
  }

  Future<void> _openFilters() async {
    var level = _level;
    var day = _day;
    final priceController = TextEditingController(
      text: _priceText(_maxPriceCents),
    );
    final apply = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            MediaQuery.of(context).viewInsets.bottom + AppSpacing.md,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Filtres', style: Theme.of(context).textTheme.titleLarge),
                const CoachSectionTitle('Niveau'),
                Wrap(
                  spacing: AppSpacing.xs,
                  children: [
                    ChoiceChip(
                      label: const Text('Tous'),
                      selected: level == null,
                      onSelected: (_) => setSheet(() => level = null),
                    ),
                    for (final l in CoachLevel.values)
                      ChoiceChip(
                        label: Text(l.label),
                        selected: level == l,
                        onSelected: (_) => setSheet(() => level = l),
                      ),
                  ],
                ),
                const CoachSectionTitle('Date'),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: day ?? now,
                            firstDate: DateTime(now.year, now.month, now.day),
                            lastDate: now.add(const Duration(days: 365)),
                          );
                          if (picked != null) setSheet(() => day = picked);
                        },
                        icon: const Icon(Icons.event_outlined),
                        label: Text(day == null
                            ? 'Toutes les dates'
                            : coachDay(day!)),
                      ),
                    ),
                    if (day != null)
                      IconButton(
                        tooltip: 'Retirer la date',
                        onPressed: () => setSheet(() => day = null),
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
                const CoachSectionTitle('Prix maximum'),
                TextField(
                  controller: priceController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    hintText: 'Illimité',
                    suffixText: 'DT',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: const Text('Appliquer les filtres'),
                ),
                TextButton(
                  onPressed: () {
                    setSheet(() {
                      level = null;
                      day = null;
                      priceController.clear();
                    });
                  },
                  child: const Text('Réinitialiser'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final priceText = priceController.text;
    priceController.dispose();
    if (apply != true || !mounted) return;
    setState(() {
      _level = level;
      _day = day;
      _maxPriceCents =
          priceText.trim().isEmpty ? null : parseDinarsToCents(priceText);
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFilters = _activeFilters > 0 ||
        _type != null ||
        _placeController.text.trim().isNotEmpty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.xs, AppSpacing.md, 0),
          child: TextField(
            controller: _placeController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _reload(),
            decoration: InputDecoration(
              hintText: 'Lieu (ville, quartier, salle…)',
              prefixIcon: const Icon(Icons.place_outlined),
              suffixIcon: IconButton(
                tooltip: 'Rechercher',
                onPressed: _reload,
                icon: const Icon(Icons.search),
              ),
            ),
          ),
        ),
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            children: [
              FilterChip(
                avatar: const Icon(Icons.my_location, size: 18),
                label: const Text('Près de moi'),
                selected: _nearMe,
                onSelected: (_) => _toggleNearMe(),
              ),
              const SizedBox(width: AppSpacing.xs),
              ActionChip(
                avatar: const Icon(Icons.tune, size: 18),
                label: Text(_activeFilters == 0
                    ? 'Filtres'
                    : 'Filtres ($_activeFilters)'),
                onPressed: _openFilters,
              ),
              const SizedBox(width: AppSpacing.xs),
              ChoiceChip(
                label: const Text('Tous les sports'),
                selected: _type == null,
                onSelected: (_) => setState(() {
                  _type = null;
                  _future = _load();
                }),
              ),
              for (final t in CoachSessionType.values) ...[
                const SizedBox(width: AppSpacing.xs),
                ChoiceChip(
                  avatar: Icon(coachTypeIcon(t), size: 18),
                  label: Text(t.label),
                  selected: _type == t,
                  onSelected: (_) => setState(() {
                    _type = t;
                    _future = _load();
                  }),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: CoachAsyncView<List<CoachSessionDto>>(
            future: _future,
            onRetry: _reload,
            builder: (context, sessions) {
              return RefreshIndicator(
                color: CoachColors.brandDeep,
                onRefresh: () async {
                  _reload();
                  await _future.catchError((_) => <CoachSessionDto>[]);
                },
                child: sessions.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: AppSpacing.xl),
                          const EmptyState(
                            icon: Icons.fitness_center_outlined,
                            title: 'Aucune séance trouvée',
                            message:
                                'Essayez un autre sport, une autre date ou '
                                'élargissez votre recherche.',
                            color: AppColors.moduleCoachProche,
                          ),
                          if (hasFilters)
                            Center(
                              child: TextButton(
                                onPressed: _resetFilters,
                                child: const Text('Réinitialiser les filtres'),
                              ),
                            ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(AppSpacing.md),
                        itemCount: sessions.length + 1,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return Text(
                              _nearMe
                                  ? '${sessions.length} séance${sessions.length > 1 ? 's' : ''}, les plus proches d\'abord'
                                  : '${sessions.length} séance${sessions.length > 1 ? 's' : ''} à venir',
                              style: theme.textTheme.bodySmall,
                            );
                          }
                          final s = sessions[i - 1];
                          return CoachSessionCard(
                            session: s,
                            onTap: () async {
                              await pushCoach<void>(
                                context,
                                CoachSessionDetailScreen(
                                  session: widget.session,
                                  initial: s,
                                ),
                              );
                              if (mounted) _reload();
                            },
                          );
                        },
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}
