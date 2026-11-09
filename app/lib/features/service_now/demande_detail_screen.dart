import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:proxilife_shared/proxilife_shared.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/live/live_refresh.dart';
import '../../core/session/session_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/money_text.dart';
import '../../core/widgets/primary_button.dart';
import '../reservations/reservation_api.dart' show apiErrorMessage;
import 'demande_form_screen.dart';
import 'service_now_api.dart';
import 'service_now_chat_screen.dart';
import 'service_now_format.dart';
import 'service_now_location.dart';
import 'service_now_report_screen.dart';
import 'service_now_scan_screen.dart';
import 'service_now_sheets.dart';
import 'service_now_tracking_screen.dart';
import 'widgets/service_now_widgets.dart';

/// A request and its intervention, with the actions open to the viewer.
class DemandeDetailScreen extends StatefulWidget {
  const DemandeDetailScreen({
    super.key,
    required this.session,
    required this.demande,
  });

  final SessionController session;
  final DemandeServiceDto demande;

  @override
  State<DemandeDetailScreen> createState() => _DemandeDetailScreenState();
}

class _DemandeDetailScreenState extends State<DemandeDetailScreen>
    with LiveRefresh<DemandeDetailScreen> {
  late final ServiceNowApi _api = ServiceNowApi(widget.session.api);
  late DemandeServiceDto _demande = widget.demande;
  late Future<List<NearbyPrestataireDto>> _nearby =
      _api.nearbyPrestataires(widget.demande.id);
  bool _busy = false;

  @override
  Future<void> liveRefresh() async {
    if (_busy) return;
    final fresh = await _api.demande(_demande.id);
    if (mounted && !_busy) setState(() => _demande = fresh);
  }

  /// Runs an action that returns the updated request.
  Future<void> _run(
    Future<DemandeServiceDto> Function() action,
    String success,
  ) async {
    setState(() => _busy = true);
    try {
      final updated = await action();
      if (!mounted) return;
      setState(() => _demande = updated);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message, String action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Non'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed == true && mounted;
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            DemandeFormScreen(session: widget.session, initial: _demande),
      ),
    );
    if (saved != true || !mounted) return;
    await _run(() => _api.demande(_demande.id), 'Demande modifiée');
    if (mounted) {
      setState(() => _nearby = _api.nearbyPrestataires(_demande.id));
    }
  }

  Future<void> _cancel() async {
    final confirmed = await _confirm(
      'Annuler cette demande ?',
      _demande.intervention == null
          ? 'Votre demande sera retirée.'
          : 'Le prestataire sera libéré de cette intervention.',
      'Oui, annuler',
    );
    if (confirmed) {
      await _run(() => _api.cancel(_demande.id), 'Demande annulée');
    }
  }

  Future<void> _accept() async {
    final result = await showAcceptSheet(context, _demande, _api);
    if (result == null || !mounted) return;
    await _run(
      () => _api.accept(
        _demande.id,
        datePrevue: result.datePrevue,
        prixCentimes: result.prixCentimes,
      ),
      'Demande acceptée',
    );
  }

  /// The prestataire scans the client's code: proof that he is there.
  Future<void> _start(InterventionDto intervention) async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const ServiceNowScanScreen()),
    );
    if (code == null || !mounted) return;
    await _run(
      () => _api.start(intervention.id, code),
      'Présence confirmée, intervention démarrée',
    );
  }

  Future<void> _openTracking(
    InterventionDto intervention, {
    required bool share,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ServiceNowTrackingScreen(
          session: widget.session,
          interventionId: intervention.id,
          shareLocation: share,
        ),
      ),
    );
  }

  /// The prestataire leaves: shares his position with the client.
  Future<void> _goOnRoute(InterventionDto intervention) async {
    final position = await locateWithConsent(
      context,
      'Votre position sera partagée avec le client pendant votre trajet, '
      'et plus du tout une fois sur place.',
    );
    if (position == null || !mounted) return;
    await _run(
      () => _api.startTrip(
        intervention.id,
        latitude: position.latitude,
        longitude: position.longitude,
      ),
      'Le client peut suivre votre trajet',
    );
    if (mounted && _demande.intervention?.enRouteLe != null) {
      await _openTracking(intervention, share: true);
    }
  }

  Future<void> _addPhoto(
    InterventionDto intervention,
    InterventionPhotoKind kind,
  ) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1280,
        imageQuality: 80,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo indisponible sur cet appareil')),
        );
      }
      return;
    }
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    final photo = _api.photoSource(intervention.id, kind);
    await _run(
      () => _api.addPhoto(intervention.id, kind, base64Encode(bytes)),
      'Photo ajoutée',
    );
    await NetworkImage(photo.url, headers: photo.headers).evict();
    if (mounted) setState(() {});
  }

  Future<void> _rate(InterventionDto intervention) async {
    final result = await showRateSheet(context);
    if (result == null || !mounted) return;
    await _run(
      () => _api.rate(
        intervention.id,
        note: result.note,
        commentaire: result.commentaire,
      ),
      'Merci pour votre avis',
    );
  }

  Future<void> _finish(InterventionDto intervention) async {
    final result = await showFinishSheet(context, intervention);
    if (result == null || !mounted) return;
    await _run(
      () => _api.finish(
        intervention.id,
        rapport: result.rapport,
        prixCentimes: result.prixCentimes,
      ),
      'Intervention terminée',
    );
  }

  Future<void> _withdraw(InterventionDto intervention) async {
    final confirmed = await _confirm(
      'Vous désister ?',
      'La demande sera de nouveau proposée aux autres prestataires.',
      'Me désister',
    );
    if (confirmed) {
      await _run(() => _api.withdraw(intervention.id), 'Désistement enregistré');
    }
  }

  Future<void> _pay(InterventionDto intervention) async {
    final methodId =
        await showPaySheet(context, widget.session, intervention.prixCentimes);
    if (methodId == null || !mounted) return;
    await _run(
      () => _api.pay(intervention.id, methodId),
      'Paiement enregistré',
    );
    try {
      await widget.session.refreshUser();
    } catch (_) {
      // Only the displayed balance is late: the live refresh will catch up.
    }
  }

  Future<void> _call(String phone) async {
    final opened = await launchUrl(Uri(scheme: 'tel', path: phone));
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de lancer l\'appel')),
      );
    }
  }

  Future<void> _push(Widget screen) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => screen));

  List<Widget> _actions() {
    final d = _demande;
    final user = widget.session.user;
    final intervention = d.intervention;
    final isOwner = d.clientId == user?.id;
    final isAdmin = user?.role == UserRole.admin;
    final isPrestataire = user?.role == UserRole.prestataire;
    final assigned =
        intervention?.prestataireId == user?.id ? intervention : null;
    final planned =
        assigned?.statut == InterventionStatus.planifiee ? assigned : null;
    final working =
        assigned?.statut == InterventionStatus.enCours ? assigned : null;

    Widget spaced(Widget child) => Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: SizedBox(width: double.infinity, child: child),
        );
    final canCancel = isAdmin
        ? ServiceNowRules.canMoveDemande(d.statut, DemandeServiceStatus.annulee)
        : isOwner && ServiceNowRules.clientCanCancel(d.statut);

    return [
      if (isPrestataire && d.statut == DemandeServiceStatus.enAttente)
        spaced(PrimaryButton(
          label: 'Accepter cette demande',
          icon: Icons.check,
          isLoading: _busy,
          onPressed: _accept,
        )),
      if (planned != null && planned.enRouteLe == null)
        spaced(OutlinedButton.icon(
          onPressed: _busy ? null : () => _goOnRoute(planned),
          icon: const Icon(Icons.directions_car_outlined),
          label: const Text('Je pars chez le client'),
        )),
      if (planned != null && planned.enRouteLe != null)
        spaced(OutlinedButton.icon(
          onPressed:
              _busy ? null : () => _openTracking(planned, share: true),
          icon: const Icon(Icons.share_location),
          label: const Text('Partager ma position'),
        )),
      if (planned != null)
        spaced(PrimaryButton(
          label: 'Scanner le code du client',
          icon: Icons.qr_code_scanner,
          isLoading: _busy,
          onPressed: () => _start(planned),
        )),
      if (isOwner &&
          intervention != null &&
          intervention.statut == InterventionStatus.planifiee &&
          intervention.enRouteLe != null)
        spaced(PrimaryButton(
          label: 'Suivre le prestataire',
          icon: Icons.map_outlined,
          isLoading: _busy,
          onPressed: () => _openTracking(intervention, share: false),
        )),
      if (isOwner &&
          intervention != null &&
          ServiceNowRules.canRate(
            intervention.statut,
            intervention.paiementStatut,
            alreadyRated: intervention.note != null,
          ))
        spaced(OutlinedButton.icon(
          onPressed: _busy ? null : () => _rate(intervention),
          icon: const Icon(Icons.star_border),
          label: const Text('Noter le prestataire'),
        )),
      if (working != null)
        spaced(PrimaryButton(
          label: 'Terminer l\'intervention',
          icon: Icons.task_alt,
          isLoading: _busy,
          onPressed: () => _finish(working),
        )),
      if (isOwner &&
          intervention != null &&
          ServiceNowRules.canPay(
              intervention.statut, intervention.paiementStatut))
        spaced(PrimaryButton(
          label: 'Payer ${MoneyText.format(intervention.prixCentimes)}',
          icon: Icons.payments_outlined,
          isLoading: _busy,
          onPressed: () => _pay(intervention),
        )),
      if ((isOwner || assigned != null) &&
          intervention != null &&
          ServiceNowRules.canChat(d.statut))
        spaced(OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _push(ServiceNowChatScreen(
                    session: widget.session,
                    demandeId: d.id,
                  )),
          icon: const Icon(Icons.chat_bubble_outline),
          label: const Text('Discuter'),
        )),
      if ((isOwner || assigned != null) &&
          intervention?.statut == InterventionStatus.terminee)
        spaced(OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _push(ServiceNowReportScreen(
                    session: widget.session,
                    demande: d,
                  )),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Rapport PDF'),
        )),
      if (isOwner && ServiceNowRules.clientCanEdit(d.statut))
        spaced(OutlinedButton.icon(
          onPressed: _busy ? null : _edit,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Modifier'),
        )),
      if (planned != null)
        spaced(TextButton(
          onPressed: _busy ? null : () => _withdraw(planned),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: const Text('Me désister'),
        )),
      if (canCancel)
        spaced(TextButton(
          onPressed: _busy ? null : _cancel,
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: const Text('Annuler la demande'),
        )),
    ];
  }

  String? _paymentLabel(InterventionDto intervention) =>
      switch (intervention.paiementStatut) {
        TransactionStatus.paye => 'Payée',
        TransactionStatus.enAttente =>
          'Paiement en espèces à confirmer par le prestataire',
        TransactionStatus.rembourse => 'Remboursée',
        TransactionStatus.echoue || null =>
          intervention.statut == InterventionStatus.terminee
              ? 'En attente de paiement'
              : null,
      };

  Widget _contact(String label, String name, String? phone) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              Text(name, style: theme.textTheme.titleMedium),
            ],
          ),
        ),
        if (phone != null)
          IconButton(
            tooltip: 'Appeler $name',
            icon: const Icon(Icons.call_outlined, color: AppColors.primary),
            onPressed: () => _call(phone),
          ),
      ],
    );
  }

  Widget _presenceCode(String code) {
    final theme = Theme.of(context);
    return _section([
      Text('Code de présence', style: theme.textTheme.titleMedium),
      const SizedBox(height: AppSpacing.xxs),
      Text(
        'Montrez-le au prestataire à son arrivée pour démarrer l\'intervention.',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: AppSpacing.sm),
      Center(
        child: QrImageView(
          data: code,
          size: 200,
          backgroundColor: Colors.white,
          semanticsLabel: 'Code de présence $code',
        ),
      ),
      Center(child: Text(code, style: theme.textTheme.titleLarge)),
    ]);
  }

  Widget _photoSlot(InterventionDto intervention, InterventionPhotoKind kind) {
    final theme = Theme.of(context);
    final exists = kind == InterventionPhotoKind.avant
        ? intervention.aPhotoAvant
        : intervention.aPhotoApres;
    final canAdd = intervention.prestataireId == widget.session.user?.id &&
        intervention.statut == InterventionStatus.enCours;
    final photo = _api.photoSource(intervention.id, kind);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(kind.label, style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.xxs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: SizedBox(
              height: 120,
              width: double.infinity,
              child: Material(
                color: AppColors.outlineSoft,
                child: InkWell(
                  onTap: canAdd && !_busy
                      ? () => _addPhoto(intervention, kind)
                      : null,
                  child: exists
                      ? Image.network(
                          photo.url,
                          headers: photo.headers,
                          fit: BoxFit.cover,
                          semanticLabel: 'Photo ${kind.label.toLowerCase()}',
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.broken_image_outlined),
                        )
                      : Icon(
                          canAdd
                              ? Icons.add_a_photo_outlined
                              : Icons.image_not_supported_outlined,
                          color: AppColors.textSecondaryStrong,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _nearbySection() {
    final theme = Theme.of(context);
    return FutureBuilder<List<NearbyPrestataireDto>>(
      future: _nearby,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <NearbyPrestataireDto>[];
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: _section([
            Text('Prestataires recommandés',
                style: theme.textTheme.titleMedium),
            for (final item in items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  item.specialiste
                      ? Icons.verified_outlined
                      : Icons.person_outline,
                  color: AppColors.primary,
                ),
                title: Text(item.nom),
                subtitle: Text([
                  formatRating(item.noteMoyenne, item.nbNotes),
                  if (item.distanceKm != null)
                    formatDistanceKm(item.distanceKm!),
                  if (item.specialiste) 'Spécialiste',
                ].join(' · ')),
              ),
          ]),
        );
      },
    );
  }

  Widget _section(List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = _demande;
    final intervention = d.intervention;
    final payment =
        intervention == null ? null : _paymentLabel(intervention);
    final isOwner = d.clientId == widget.session.user?.id;
    return Scaffold(
      appBar: AppBar(title: Text(d.type.label)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Row(
              children: [
                Icon(serviceTypeIcon(d.type), color: AppColors.primary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Demande n° ${d.id}',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                DemandeStatusBadge(d.statut),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _section([
              Text('Besoin', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xxs),
              Text(d.description, style: theme.textTheme.bodyLarge),
              const SizedBox(height: AppSpacing.xs),
              InfoLine(icon: Icons.place_outlined, text: d.adresse),
              InfoLine(
                icon: Icons.event_outlined,
                text: 'Souhaitée le ${formatServiceDate(d.dateSouhaitee)}',
              ),
              if (!isOwner) ...[
                const SizedBox(height: AppSpacing.sm),
                _contact('Client', d.clientNom, d.clientTelephone),
              ],
            ]),
            if (intervention != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _section([
                Text(
                  'Intervention · ${intervention.statut.label}',
                  style: theme.textTheme.titleMedium,
                ),
                if (intervention.prestataireNom != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  _contact(
                    'Prestataire',
                    intervention.prestataireNom!,
                    intervention.prestataireId == widget.session.user?.id
                        ? null
                        : intervention.prestataireTelephone,
                  ),
                ],
                InfoLine(
                  icon: Icons.star_outline,
                  text: formatRating(
                    intervention.prestataireNoteMoyenne,
                    intervention.prestataireNbNotes,
                  ),
                ),
                InfoLine(
                  icon: Icons.schedule,
                  text: 'Prévue le ${formatServiceDate(intervention.datePrevue)}',
                ),
                if (intervention.dateDebut != null)
                  InfoLine(
                    icon: Icons.play_arrow_outlined,
                    text:
                        'Débutée le ${formatServiceDate(intervention.dateDebut!)}',
                  ),
                if (intervention.dateFin != null)
                  InfoLine(
                    icon: Icons.task_alt,
                    text:
                        'Terminée le ${formatServiceDate(intervention.dateFin!)}',
                  ),
                InfoLine(
                  icon: Icons.payments_outlined,
                  text: payment == null
                      ? MoneyText.format(intervention.prixCentimes)
                      : '${MoneyText.format(intervention.prixCentimes)} · $payment',
                ),
                if (intervention.rapport != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text('Rapport', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(intervention.rapport!,
                      style: theme.textTheme.bodyLarge),
                ],
                if (intervention.note != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  InfoLine(
                    icon: Icons.star,
                    text: intervention.commentaire == null
                        ? 'Note du client : ${intervention.note}/5'
                        : 'Note du client : ${intervention.note}/5 · '
                            '${intervention.commentaire}',
                  ),
                ],
                if (intervention.statut == InterventionStatus.enCours ||
                    intervention.aPhotoAvant ||
                    intervention.aPhotoApres) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text('Photos', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xxs),
                  Row(
                    children: [
                      _photoSlot(intervention, InterventionPhotoKind.avant),
                      const SizedBox(width: AppSpacing.sm),
                      _photoSlot(intervention, InterventionPhotoKind.apres),
                    ],
                  ),
                ],
              ]),
              if (isOwner && intervention.qrCode != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _presenceCode(intervention.qrCode!),
              ],
            ],
            if (isOwner && d.statut == DemandeServiceStatus.enAttente)
              _nearbySection(),
            ..._actions(),
          ],
        ),
      ),
    );
  }
}
