import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/session/session_controller.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/primary_button.dart';
import '../reservations/reservation_api.dart' show apiErrorMessage;
import 'service_now_api.dart';

/// Weekly hours and days off of a prestataire. Smart matching and the
/// acceptance of a request both use this calendar.
class PrestataireAvailabilityScreen extends StatefulWidget {
  const PrestataireAvailabilityScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<PrestataireAvailabilityScreen> createState() =>
      _PrestataireAvailabilityScreenState();
}

class _PrestataireAvailabilityScreenState
    extends State<PrestataireAvailabilityScreen> {
  static const List<String> _days = [
    'Lundi',
    'Mardi',
    'Mercredi',
    'Jeudi',
    'Vendredi',
    'Samedi',
    'Dimanche',
  ];
  static const TimeOfDay _defaultStart = TimeOfDay(hour: 8, minute: 0);
  static const TimeOfDay _defaultEnd = TimeOfDay(hour: 18, minute: 0);

  late final ServiceNowApi _api = ServiceNowApi(widget.session.api);

  /// Enabled days only, by `DateTime.weekday` (1 = lundi).
  final Map<int, ({TimeOfDay start, TimeOfDay end})> _hours = {};
  final Set<String> _daysOff = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  TimeOfDay _time(int minutes) =>
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  int _minutes(TimeOfDay time) => time.hour * 60 + time.minute;

  String _label(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  /// "12/11/2026" from a stored "2026-11-12".
  String _dayLabel(String key) => key.split('-').reversed.join('/');

  Future<void> _load() async {
    try {
      final calendar = await _api.calendar();
      if (!mounted) return;
      setState(() {
        for (final slot in calendar.creneaux) {
          _hours[slot.jour] = (
            start: _time(slot.debutMinutes),
            end: _time(slot.finMinutes),
          );
        }
        _daysOff.addAll(calendar.joursOff);
      });
    } catch (e) {
      if (mounted) _snack(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickTime(int day, {required bool isStart}) async {
    final current = _hours[day];
    if (current == null) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? current.start : current.end,
      cancelText: 'Annuler',
      confirmText: 'OK',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _hours[day] = (
        start: isStart ? picked : current.start,
        end: isStart ? current.end : picked,
      );
    });
  }

  Future<void> _addDayOff() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: ServiceNowRules.maxDaysAhead)),
      helpText: 'Jour non travaillé',
      cancelText: 'Annuler',
      confirmText: 'OK',
    );
    if (date == null || !mounted) return;
    setState(() => _daysOff.add(ServiceNowRules.dayKey(date)));
  }

  Future<void> _save() async {
    final slots = [
      for (final entry in _hours.entries)
        DisponibiliteSlotDto(
          jour: entry.key,
          debutMinutes: _minutes(entry.value.start),
          finMinutes: _minutes(entry.value.end),
        ),
    ];
    for (final slot in slots) {
      final error = ServiceNowRules.slotError(slot);
      if (error != null) {
        _snack('${_days[slot.jour - 1]} : $error');
        return;
      }
    }
    setState(() => _saving = true);
    try {
      await _api.saveCalendar(PrestataireDisponibiliteDto(
        creneaux: slots,
        joursOff: _daysOff.toList()..sort(),
      ));
      if (!mounted) return;
      _snack('Disponibilités enregistrées');
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) _snack(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _dayRow(int day) {
    final hours = _hours[day];
    return Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_days[day - 1]),
          subtitle: hours == null ? const Text('Non travaillé') : null,
          value: hours != null,
          onChanged: (enabled) => setState(() {
            if (enabled) {
              _hours[day] = (start: _defaultStart, end: _defaultEnd);
            } else {
              _hours.remove(day);
            }
          }),
        ),
        if (hours != null)
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickTime(day, isStart: true),
                  child: Text('De ${_label(hours.start)}'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickTime(day, isStart: false),
                  child: Text('À ${_label(hours.end)}'),
                ),
              ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final daysOff = _daysOff.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('Mes disponibilités')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  Text('Horaires de la semaine',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Sans horaires, vous êtes considéré disponible tous les jours.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  for (var day = 1; day <= 7; day++) _dayRow(day),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Jours non travaillés',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final day in daysOff)
                        InputChip(
                          label: Text(_dayLabel(day)),
                          onDeleted: () =>
                              setState(() => _daysOff.remove(day)),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 18),
                        label: const Text('Ajouter un jour'),
                        onPressed: _addDayOff,
                      ),
                    ],
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
