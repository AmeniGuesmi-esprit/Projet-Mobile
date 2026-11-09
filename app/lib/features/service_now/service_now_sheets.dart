import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/session/session_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/money_text.dart';
import '../../core/widgets/primary_button.dart';
import '../payment/payment_api.dart';
import '../payment/payment_methods_screen.dart';
import '../reservations/reservation_api.dart' show apiErrorMessage;
import 'service_now_api.dart';
import 'service_now_format.dart';
import 'widgets/service_now_widgets.dart';

/// Quick forms of the detail screen. Each returns the entered values, or
/// null when the sheet is dismissed.
Future<({DateTime datePrevue, int prixCentimes})?> showAcceptSheet(
  BuildContext context,
  DemandeServiceDto demande,
  ServiceNowApi api,
) =>
    showModalBottomSheet<({DateTime datePrevue, int prixCentimes})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AcceptSheet(demande: demande, api: api),
    );

Future<({int note, String? commentaire})?> showRateSheet(
  BuildContext context,
) =>
    showModalBottomSheet<({int note, String? commentaire})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _RateSheet(),
    );

Future<({String rapport, int prixCentimes})?> showFinishSheet(
  BuildContext context,
  InterventionDto intervention,
) =>
    showModalBottomSheet<({String rapport, int prixCentimes})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FinishSheet(intervention: intervention),
    );

/// Returns the id of the chosen payment method.
Future<int?> showPaySheet(
  BuildContext context,
  SessionController session,
  int amountCentimes,
) =>
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PaySheet(session: session, amountCentimes: amountCentimes),
    );

/// Shared layout: scrollable, and lifted above the keyboard.
class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            ...children,
          ],
        ),
      ),
    );
  }
}

String? _priceValidator(String? value) {
  final cents = parseDinars(value ?? '');
  if (cents == null) return 'Saisissez un montant, par exemple 45,50';
  return ServiceNowRules.priceError(cents);
}

class _AcceptSheet extends StatefulWidget {
  const _AcceptSheet({required this.demande, required this.api});

  final DemandeServiceDto demande;
  final ServiceNowApi api;

  @override
  State<_AcceptSheet> createState() => _AcceptSheetState();
}

class _AcceptSheetState extends State<_AcceptSheet> {
  final _formKey = GlobalKey<FormState>();
  final _price = TextEditingController();
  late DateTime? _date = _initialDate();
  late final Future<PriceEstimateDto> _estimate =
      widget.api.estimate(widget.demande.type);
  String? _dateError;

  DateTime? _initialDate() {
    final wanted = widget.demande.dateSouhaitee.toLocal();
    return wanted.isAfter(DateTime.now()) ? wanted : null;
  }

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  String? _validateDate() {
    final date = _date;
    if (date == null) return 'Choisissez une date';
    return ServiceNowRules.scheduleError(date, now: DateTime.now());
  }

  void _submit() {
    final formValid = _formKey.currentState!.validate();
    final dateError = _validateDate();
    setState(() => _dateError = dateError);
    if (!formValid || dateError != null) return;
    Navigator.of(context).pop((
      datePrevue: _date!,
      prixCentimes: parseDinars(_price.text)!,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: _SheetBody(
        title: 'Accepter la demande',
        children: [
          DateTimeField(
            label: 'Date de l\'intervention',
            value: _date,
            errorText: _dateError,
            onChanged: (value) => setState(() {
              _date = value;
              _dateError = _validateDate();
            }),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Prix proposé',
              suffixText: 'DT',
            ),
            validator: _priceValidator,
          ),
          FutureBuilder<PriceEstimateDto>(
            future: _estimate,
            builder: (context, snapshot) {
              final estimate = snapshot.data;
              if (estimate == null) return const SizedBox.shrink();
              return InfoLine(
                icon: Icons.sell_outlined,
                text: 'Prix habituel : '
                    '${MoneyText.format(estimate.minCentimes)} à '
                    '${MoneyText.format(estimate.maxCentimes)}',
              );
            },
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(label: 'Confirmer', onPressed: _submit),
        ],
      ),
    );
  }
}

class _RateSheet extends StatefulWidget {
  const _RateSheet();

  @override
  State<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<_RateSheet> {
  final _comment = TextEditingController();
  int _note = 0;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  void _submit() {
    final comment = _comment.text.trim();
    Navigator.of(context).pop((
      note: _note,
      commentaire: comment.isEmpty ? null : comment,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return _SheetBody(
      title: 'Noter le prestataire',
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var star = 1; star <= 5; star++)
              IconButton(
                tooltip: '$star sur 5',
                iconSize: 40,
                onPressed: () => setState(() => _note = star),
                icon: Icon(
                  star <= _note ? Icons.star : Icons.star_border,
                  color: AppColors.warning,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _comment,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Commentaire (facultatif)',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        PrimaryButton(
          label: 'Envoyer la note',
          onPressed: _note == 0 ? null : _submit,
        ),
      ],
    );
  }
}

class _FinishSheet extends StatefulWidget {
  const _FinishSheet({required this.intervention});

  final InterventionDto intervention;

  @override
  State<_FinishSheet> createState() => _FinishSheetState();
}

class _FinishSheetState extends State<_FinishSheet> {
  final _formKey = GlobalKey<FormState>();
  final _report = TextEditingController();
  late final TextEditingController _price = TextEditingController(
    text: dinarsText(widget.intervention.prixCentimes),
  );

  @override
  void dispose() {
    _report.dispose();
    _price.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop((
      rapport: _report.text.trim(),
      prixCentimes: parseDinars(_price.text)!,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: _SheetBody(
        title: 'Terminer l\'intervention',
        children: [
          TextFormField(
            controller: _report,
            keyboardType: TextInputType.multiline,
            minLines: 3,
            maxLines: 6,
            maxLength: ServiceNowRules.maxReportLength,
            decoration: const InputDecoration(
              labelText: 'Rapport d\'intervention',
              alignLabelWithHint: true,
            ),
            validator: (value) => ServiceNowRules.reportError(value ?? ''),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Prix final',
              suffixText: 'DT',
            ),
            validator: _priceValidator,
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(label: 'Terminer', onPressed: _submit),
        ],
      ),
    );
  }
}

class _PaySheet extends StatefulWidget {
  const _PaySheet({required this.session, required this.amountCentimes});

  final SessionController session;
  final int amountCentimes;

  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> {
  late final Future<List<PaymentMethodDto>> _methods =
      PaymentApi(widget.session.api).listMethods();

  String _label(PaymentMethodDto method) => switch (method.type) {
        PaymentMethodType.carteBancaire =>
          'Carte •••• ${method.quatreDerniersChiffres ?? ''}',
        PaymentMethodType.portefeuille => 'Portefeuille ProxiLife',
        PaymentMethodType.especes => 'Espèces au prestataire',
      };

  IconData _icon(PaymentMethodType type) => switch (type) {
        PaymentMethodType.carteBancaire => Icons.credit_card,
        PaymentMethodType.portefeuille => Icons.account_balance_wallet_outlined,
        PaymentMethodType.especes => Icons.payments_outlined,
      };

  void _addMethod() {
    final navigator = Navigator.of(context);
    final api = widget.session.api;
    navigator.pop();
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => PaymentMethodsScreen(api: api)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SheetBody(
      title: 'Payer ${MoneyText.format(widget.amountCentimes)}',
      children: [
        FutureBuilder<List<PaymentMethodDto>>(
          future: _methods,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Text(apiErrorMessage(snapshot.error!));
            }
            final methods = snapshot.data ?? const <PaymentMethodDto>[];
            if (methods.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Ajoutez d\'abord un moyen de paiement.'),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton(
                    onPressed: _addMethod,
                    child: const Text('Ajouter un moyen de paiement'),
                  ),
                ],
              );
            }
            return Column(
              children: [
                for (final method in methods)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(_icon(method.type), color: AppColors.primary),
                    title: Text(_label(method)),
                    subtitle: method.parDefaut ? const Text('Par défaut') : null,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).pop(method.id),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
