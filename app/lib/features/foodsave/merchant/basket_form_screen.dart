import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../core/session/session_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/money_text.dart';
import '../data/foodsave_api.dart';
import '../widgets/foodsave_ui.dart';
import 'widgets/basket_form_validators.dart';
import 'widgets/basket_photo_field.dart';
import 'widgets/merchant_format.dart';

/// Create (basket == null) or edit a basket. Pops with the saved [BasketDto].
class BasketFormScreen extends StatefulWidget {
  const BasketFormScreen({super.key, required this.session, this.basket});

  final SessionController session;

  /// null = create. Pops with the saved BasketDto.
  final BasketDto? basket;

  @override
  State<BasketFormScreen> createState() => _BasketFormScreenState();
}

class _BasketFormScreenState extends State<BasketFormScreen> {
  late final FoodSaveApi _api = FoodSaveApi(widget.session.api);
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _title;
  late final TextEditingController _content;
  late final TextEditingController _price;
  late final TextEditingController _initialPrice;
  late final TextEditingController _quantity;

  late FoodCategory _category;
  late DateTime _pickupDay; // local date (time ignored)
  late TimeOfDay _startTime;

  /// End of sale; pickup is possible from the start until this moment.
  late DateTime _expiry; // local

  /// Minutes a reservation (its QR code) stays valid.
  late int _reservationMinutes;

  /// Quick choices for the reservation duration (minutes).
  static const List<int> _durationChoices = [15, 30, 45, 60, 90, 120];

  PickedPhoto? _photo;
  bool _submitting = false;
  String? _formError;

  bool get _creating => widget.basket == null;
  bool get _editable =>
      _creating || FoodSaveRules.isBasketEditable(widget.basket!.statut);

  @override
  void initState() {
    super.initState();
    final b = widget.basket;
    _title = TextEditingController(text: b?.titre ?? '');
    _content = TextEditingController(text: b?.contenu ?? '');
    _price = TextEditingController(
        text: b == null ? '' : centsToInput(b.prixCentimes));
    _initialPrice = TextEditingController(
        text: b == null ? '' : centsToInput(b.prixInitialCentimes));
    _quantity = TextEditingController(text: '${b?.quantite ?? 5}');
    _category = b?.categorie ?? FoodCategory.mixte;

    if (b != null) {
      final start = b.creneauRetraitDebut.toLocal();
      _pickupDay = DateTime(start.year, start.month, start.day);
      _startTime = TimeOfDay.fromDateTime(start);
      _expiry = b.dateExpiration.toLocal();
      _reservationMinutes = b.dureeReservationMinutes;
    } else {
      // Starts now (today, current time); on sale for 2 hours by default.
      final now = DateTime.now();
      _pickupDay = DateTime(now.year, now.month, now.day);
      _startTime = TimeOfDay.fromDateTime(now);
      _expiry = _pickupStart.add(const Duration(hours: 2));
      _reservationMinutes = foodSaveDefaultReservationMinutes;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _price.dispose();
    _initialPrice.dispose();
    _quantity.dispose();
    super.dispose();
  }

  DateTime _at(DateTime day, TimeOfDay t) =>
      DateTime(day.year, day.month, day.day, t.hour, t.minute);
  DateTime get _pickupStart => _at(_pickupDay, _startTime);

  /// Earliest allowed expiry: 1 h after the start (server rule).
  DateTime get _minExpiry => _pickupStart.add(foodSaveMinOpenDuration);

  /// Keeps the expiry at least 1 h after a start that moved later.
  void _syncExpiry() {
    if (_expiry.isBefore(_minExpiry)) _expiry = _minExpiry;
    _fitDuration();
  }

  /// Minutes between the start and the expiry: the longest possible
  /// reservation duration.
  int get _openMinutes => _expiry.difference(_pickupStart).inMinutes;

  /// Duration choices that fit between the start and the expiry
  /// (e.g. 22:00 → 23:00: 15, 30, 45 min and 1 h).
  List<int> get _allowedDurations =>
      {..._durationChoices, _reservationMinutes}
          .where((m) => m <= _openMinutes)
          .toList()
        ..sort();

  /// Shortens the selected duration when the sale got shorter.
  void _fitDuration() {
    if (_reservationMinutes <= _openMinutes) return;
    final fitting = _durationChoices.where((m) => m <= _openMinutes);
    _reservationMinutes =
        fitting.isEmpty ? foodSaveMinReservationMinutes : fitting.last;
  }

  // ------------------------------------------------------------ pickers

  Widget _pickerTheme(BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      );

  Future<DateTime?> _pickDate(DateTime initial, String help) {
    final today = DateTime.now();
    final first = DateTime(today.year, today.month, today.day);
    return showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : initial,
      firstDate: initial.isBefore(first) ? initial : first,
      lastDate: first.add(const Duration(days: 60)),
      helpText: help,
      cancelText: 'Annuler',
      confirmText: 'Valider',
      fieldLabelText: 'Date',
      fieldHintText: 'jj/mm/aaaa',
      errorFormatText: 'Format de date invalide',
      errorInvalidText: 'Date hors de la période autorisée',
    );
  }

  Future<TimeOfDay?> _pickTime(TimeOfDay initial, String help) =>
      showTimePicker(
        context: context,
        initialTime: initial,
        helpText: help,
        cancelText: 'Annuler',
        confirmText: 'Valider',
        hourLabelText: 'Heure',
        minuteLabelText: 'Minute',
        errorInvalidText: 'Heure invalide',
        builder: _pickerTheme,
      );

  Future<void> _choosePickupDay() async {
    final d = await _pickDate(_pickupDay, 'Jour de début');
    if (d == null) return;
    setState(() {
      _pickupDay = d;
      _syncExpiry();
      _formError = null;
    });
  }

  Future<void> _chooseStart() async {
    final t = await _pickTime(_startTime, 'Heure de début');
    if (t == null) return;
    setState(() {
      _startTime = t;
      _syncExpiry();
      _formError = null;
    });
  }

  Future<void> _chooseExpiryDay() async {
    final d = await _pickDate(_expiry, 'Date d\'expiration');
    if (d == null) return;
    setState(() {
      _expiry = DateTime(d.year, d.month, d.day, _expiry.hour, _expiry.minute);
      _fitDuration();
      _formError = _expiryHint();
    });
  }

  Future<void> _chooseExpiryTime() async {
    final t = await _pickTime(
        TimeOfDay.fromDateTime(_expiry), 'Heure d\'expiration');
    if (t == null) return;
    setState(() {
      _expiry = _at(_expiry, t);
      _fitDuration();
      _formError = _expiryHint();
    });
  }

  /// Immediate feedback when the chosen expiry is too early.
  String? _expiryHint() => _expiry.isBefore(_minExpiry)
      ? 'L\'expiration doit être au moins 1 h après le début '
          '(${relativeDayFr(_minExpiry)} à ${formatTimeFr(_minExpiry)} '
          'au plus tôt).'
      : null;

  void _selectDuration(int minutes) => setState(() {
        _reservationMinutes = minutes;
        _formError = null;
      });

  void _stepQuantity(int delta) {
    final current = int.tryParse(_quantity.text.trim()) ?? 0;
    final min = _creating ? 1 : 0;
    final next = (current + delta).clamp(min, 999);
    _quantity.text = '$next';
    _quantity.selection = TextSelection.collapsed(offset: _quantity.text.length);
    _formKey.currentState?.validate();
  }

  // ------------------------------------------------------------- submit

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _formError = null);
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() =>
          _formError = 'Corrigez les champs signalés en rouge puis réessayez.');
      return;
    }
    final price = parseDinarsToCents(_price.text)!;
    final initial = parseDinarsToCents(_initialPrice.text)!;
    final quantity = int.parse(_quantity.text.trim());
    final start = _pickupStart;
    // Pickup is possible from the start until the expiry.
    final end = _expiry;
    final ruleError = FoodSaveRules.basketError(
      title: _title.text,
      content: _content.text,
      priceCents: price,
      initialPriceCents: initial,
      quantity: quantity,
      pickupStart: start,
      pickupEnd: end,
      expiry: _expiry,
      reservationMinutes: _reservationMinutes,
    );
    final timeError = ruleError ??
        (_creating && !end.isAfter(DateTime.now())
            ? 'La date d\'expiration doit être dans le futur'
            : null);
    if (timeError != null) {
      setState(() => _formError = timeError);
      return;
    }

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      BasketDto saved;
      String confirmation;
      final b = widget.basket;
      if (b == null) {
        final created = await _api.createBasket(
          titre: _title.text.trim(),
          contenu: _content.text.trim(),
          categorie: _category,
          prixCentimes: price,
          prixInitialCentimes: initial,
          quantite: quantity,
          creneauRetraitDebut: start,
          creneauRetraitFin: end,
          dateExpiration: _expiry,
          dureeReservationMinutes: _reservationMinutes,
        );
        saved = created.panier;
        final n = created.clientsNotifies;
        confirmation = 'Panier publié · $n client${n > 1 ? 's' : ''} à '
            'proximité notifié${n > 1 ? 's' : ''}';
      } else {
        // Only changed fields are sent: an unchanged quantity must never
        // overwrite units sold while the form was open.
        bool changed(DateTime x, DateTime y) => !x.isAtSameMomentAs(y);
        saved = await _api.updateBasket(
          b.id,
          titre: _title.text.trim() != b.titre ? _title.text.trim() : null,
          contenu:
              _content.text.trim() != b.contenu ? _content.text.trim() : null,
          categorie: _category != b.categorie ? _category : null,
          prixCentimes: price != b.prixCentimes ? price : null,
          prixInitialCentimes:
              initial != b.prixInitialCentimes ? initial : null,
          quantite: quantity != b.quantite ? quantity : null,
          creneauRetraitDebut:
              changed(start, b.creneauRetraitDebut) ? start : null,
          creneauRetraitFin: changed(end, b.creneauRetraitFin) ? end : null,
          dateExpiration:
              changed(_expiry, b.dateExpiration) ? _expiry : null,
          dureeReservationMinutes:
              _reservationMinutes != b.dureeReservationMinutes
                  ? _reservationMinutes
                  : null,
        );
        confirmation = 'Panier mis à jour';
      }

      final photo = _photo;
      if (photo != null) {
        try {
          saved = await _api.uploadBasketImage(
              saved.id, photo.bytes, photo.contentType);
        } catch (e) {
          confirmation = '$confirmation · photo non envoyée : '
              '${FoodSaveErrorView.messageOf(e)}';
        }
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(confirmation)));
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = FoodSaveErrorView.messageOf(e);
      });
    }
  }

  // -------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = _editable && !_submitting;
    return Scaffold(
      appBar: AppBar(
          title: Text(_creating ? 'Nouveau panier' : 'Modifier le panier')),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xxl),
          children: [
            if (!_editable) ...[
              _Banner(
                icon: Icons.lock_outline,
                color: AppColors.textSecondaryStrong,
                text:
                    'Ce panier est ${widget.basket!.statut.label.toLowerCase()} : il ne peut plus être modifié.',
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            BasketPhotoField(
              api: _api,
              existing: widget.basket,
              picked: _photo,
              enabled: enabled,
              onChanged: (p) => setState(() => _photo = p),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _title,
              enabled: enabled,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Titre',
                hintText: 'Ex. Panier du soir',
              ),
              validator: validateBasketTitle,
            ),
            const SizedBox(height: AppSpacing.xs),
            TextFormField(
              controller: _content,
              enabled: enabled,
              maxLength: 500,
              minLines: 3,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Contenu',
                hintText: 'Ex. 3 viennoiseries, 1 baguette, 2 parts de quiche',
                alignLabelWithHint: true,
              ),
              validator: validateBasketContent,
            ),
            const SizedBox(height: AppSpacing.sm),
            _SectionTitle('Catégorie'),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final c in FoodCategory.values)
                  ChoiceChip(
                    avatar: Icon(FoodCategoryMeta.icon(c),
                        size: 18,
                        color: c == _category
                            ? AppColors.moduleFoodSaveDeep
                            : AppColors.textSecondaryStrong),
                    label: Text(c.label),
                    selected: c == _category,
                    showCheckmark: false,
                    selectedColor: AppColors.moduleFoodSaveSoft,
                    backgroundColor: AppColors.surface,
                    side: BorderSide(
                        color: c == _category
                            ? AppColors.moduleFoodSave
                            : AppColors.outline),
                    labelStyle: TextStyle(
                      color: c == _category
                          ? AppColors.moduleFoodSaveDeep
                          : AppColors.text,
                      fontWeight:
                          c == _category ? FontWeight.w700 : FontWeight.w500,
                    ),
                    onSelected: enabled
                        ? (_) => setState(() => _category = c)
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _SectionTitle('Prix'),
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _MoneyField(
                    key: const ValueKey('field-price'),
                    controller: _price,
                    enabled: enabled,
                    label: 'Prix réduit',
                    validator: validateReducedPrice,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _MoneyField(
                    key: const ValueKey('field-initial-price'),
                    controller: _initialPrice,
                    enabled: enabled,
                    label: 'Prix initial',
                    validator: (v) => validateInitialPrice(v, _price.text),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _DiscountPreview(price: _price, initialPrice: _initialPrice),
            const SizedBox(height: AppSpacing.lg),
            _SectionTitle(_creating ? 'Quantité' : 'Unités encore en vente'),
            const SizedBox(height: AppSpacing.xs),
            _QuantityStepper(
              controller: _quantity,
              enabled: enabled,
              creating: _creating,
              onStep: _stepQuantity,
            ),
            if (!_creating)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'Les unités déjà réservées ne sont pas concernées. À 0, le panier passe en « Épuisé ».',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondaryStrong),
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            _SectionTitle('Date de début'),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Le panier est proposé et peut être retiré dès ce moment.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textSecondaryStrong),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: _PickerTile(
                    icon: Icons.event_outlined,
                    label: 'Jour',
                    value: relativeDayFr(_pickupDay),
                    onTap: enabled ? _choosePickupDay : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _PickerTile(
                    icon: Icons.schedule,
                    label: 'Heure',
                    value: formatTimeFr(_pickupStart),
                    onTap: enabled ? _chooseStart : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _SectionTitle('Date d\'expiration'),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Après cette date, le panier n\'est plus proposé ni retirable. '
              'Au moins 1 h après le début (dès '
              '${formatTimeFr(_minExpiry)}).',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textSecondaryStrong),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: _PickerTile(
                    icon: Icons.event_busy_outlined,
                    label: 'Jour',
                    value: relativeDayFr(_expiry),
                    onTap: enabled ? _chooseExpiryDay : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _PickerTile(
                    icon: Icons.timer_outlined,
                    label: 'Heure',
                    value: formatTimeFr(_expiry),
                    onTap: enabled ? _chooseExpiryTime : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _SectionTitle('Durée de réservation'),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Temps dont le client dispose pour retirer son panier après '
              'l\'avoir réservé : passé ce délai, la réservation expire et '
              'son QR code n\'est plus valide. Au plus '
              '${_durationLabel(_openMinutes.clamp(0, foodSaveMaxReservationMinutes))} '
              '(temps entre le début et l\'expiration) : les réservations '
              'ferment ${_durationLabel(_reservationMinutes)} avant '
              'l\'expiration, à ${formatTimeFr(FoodSaveRules.reservationDeadline(pickupEnd: _expiry, reservationMinutes: _reservationMinutes))}.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textSecondaryStrong),
            ),
            const SizedBox(height: AppSpacing.xs),
            if (_allowedDurations.isEmpty)
              Text(
                'Choisissez d\'abord une expiration au moins 1 h après le début.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.error),
              ),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final m in _allowedDurations)
                  ChoiceChip(
                    key: ValueKey('duration-$m'),
                    label: Text(_durationLabel(m)),
                    selected: m == _reservationMinutes,
                    showCheckmark: false,
                    avatar: m == _reservationMinutes
                        ? const Icon(Icons.timer_outlined,
                            size: 18, color: AppColors.moduleFoodSaveDeep)
                        : null,
                    selectedColor: AppColors.moduleFoodSaveSoft,
                    labelStyle: TextStyle(
                      color: m == _reservationMinutes
                          ? AppColors.moduleFoodSaveDeep
                          : AppColors.text,
                      fontWeight: m == _reservationMinutes
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                    side: BorderSide(
                        color: m == _reservationMinutes
                            ? AppColors.moduleFoodSaveDeep
                            : AppColors.outline),
                    onSelected: enabled ? (_) => _selectDuration(m) : null,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            AnimatedSize(
              duration: FoodSaveMotion.fast,
              curve: FoodSaveMotion.curve,
              child: _formError == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Semantics(
                        liveRegion: true,
                        child: _Banner(
                          icon: Icons.error_outline,
                          color: AppColors.error,
                          text: _formError!,
                        ),
                      ),
                    ),
            ),
            FilledButton(
              style: foodSaveFilledStyle(),
              onPressed: enabled ? _submit : null,
              child: AnimatedSwitcher(
                duration: FoodSaveMotion.fast,
                child: _submitting
                    ? const SizedBox(
                        key: ValueKey('loading'),
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      )
                    : Row(
                        key: const ValueKey('label'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_creating
                              ? Icons.campaign_outlined
                              : Icons.save_outlined),
                          const SizedBox(width: AppSpacing.xs),
                          Text(_creating
                              ? 'Publier le panier'
                              : 'Enregistrer les modifications'),
                        ],
                      ),
              ),
            ),
            if (_creating)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'Les clients situés à moins de ${foodSaveNotificationRadiusKm.round()} km seront notifiés.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.textSecondaryStrong),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- pieces

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(text,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.text)),
            ),
          ],
        ),
      );
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({
    super.key,
    required this.controller,
    required this.label,
    required this.validator,
    required this.enabled,
  });

  final TextEditingController controller;
  final String label;
  final FormFieldValidator<String> validator;
  final bool enabled;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.next,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          LengthLimitingTextInputFormatter(10),
        ],
        decoration: InputDecoration(
          labelText: label,
          hintText: '0,00',
          suffixText: 'DT',
          errorMaxLines: 3,
        ),
        validator: validator,
      );
}

/// Live "-67 % · Le client économise 10,00 DT" preview.
class _DiscountPreview extends StatelessWidget {
  const _DiscountPreview({required this.price, required this.initialPrice});

  final TextEditingController price;
  final TextEditingController initialPrice;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([price, initialPrice]),
        builder: (context, _) {
          final p = parseDinarsToCents(price.text);
          final i = parseDinarsToCents(initialPrice.text);
          final valid = p != null && i != null && p > 0 && i > p;
          final pct = valid ? FoodSaveRules.discountPercent(p, i) : 0;
          return AnimatedSwitcher(
            duration: FoodSaveMotion.fast,
            switchInCurve: FoodSaveMotion.curve,
            child: !valid
                ? Text(
                    key: const ValueKey('hint'),
                    'Indiquez les deux prix pour voir la réduction proposée.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondaryStrong),
                  )
                : Container(
                    key: ValueKey('preview-$pct-${i - p}'),
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.moduleFoodSaveSoft,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      children: [
                        DiscountBadge(
                            prixCentimes: p,
                            prixInitialCentimes: i,
                            large: true),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Le client économise ${MoneyText.format(i - p)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                    color: AppColors.text,
                                    fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
          );
        },
      );
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.controller,
    required this.enabled,
    required this.creating,
    required this.onStep,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool creating;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final q = int.tryParse(controller.text.trim()) ?? 0;
          final min = creating ? 1 : 0;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton.outlined(
                tooltip: 'Retirer une unité',
                constraints:
                    const BoxConstraints(minWidth: 52, minHeight: 52),
                onPressed: enabled && q > min ? () => onStep(-1) : null,
                icon: const Icon(Icons.remove),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('field-quantity'),
                  controller: controller,
                  enabled: enabled,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Unités',
                    errorMaxLines: 2,
                  ),
                  validator: (v) =>
                      validateBasketQuantity(v, creating: creating),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton.outlined(
                tooltip: 'Ajouter une unité',
                constraints:
                    const BoxConstraints(minWidth: 52, minHeight: 52),
                onPressed: enabled && q < 999 ? () => onStep(1) : null,
                icon: const Icon(Icons.add),
              ),
            ],
          );
        },
      );
}

/// Read-only field that opens a date / time picker.
class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: onTap != null,
        label: '$label : $value. Modifier',
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InputDecorator(
            isEmpty: false,
            decoration: InputDecoration(
              labelText: label,
              enabled: onTap != null,
              prefixIcon: Icon(icon, color: AppColors.moduleFoodSaveDeep),
              suffixIcon: const Icon(Icons.expand_more),
            ),
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge),
          ),
        ),
      );
}

/// "15 min", "1 h", "1 h 30".
String _durationLabel(int minutes) {
  if (minutes < 60) return '$minutes min';
  final m = minutes % 60;
  return m == 0 ? '${minutes ~/ 60} h' : '${minutes ~/ 60} h $m';
}
