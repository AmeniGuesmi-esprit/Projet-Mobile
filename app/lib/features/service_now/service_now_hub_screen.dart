import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/notifications/notification_service.dart';
import '../../core/session/session_controller.dart';
import 'demande_form_screen.dart';
import 'demande_list_view.dart';
import 'prestataire_availability_screen.dart';
import 'prestataire_profile_screen.dart';
import 'service_now_api.dart';

/// ServiceNow entry point (opened from the home screen):
///  - prestataire    : Disponibles · Mes interventions
///  - every other role asks for services : Mes demandes
class ServiceNowHubScreen extends StatefulWidget {
  const ServiceNowHubScreen({super.key, required this.session, this.visit});

  final SessionController session;

  /// How many times the bottom tab was opened; null when pushed as a page.
  final int? visit;

  @override
  State<ServiceNowHubScreen> createState() => _ServiceNowHubScreenState();
}

class _ServiceNowHubScreenState extends State<ServiceNowHubScreen> {
  late final ServiceNowApi _api = ServiceNowApi(widget.session.api);

  /// Asked once per app launch, so that a "no" is not repeated.
  static bool _notificationsOffered = false;

  /// Incremented after a creation, to reload "Mes demandes".
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    // As a bottom tab this screen is built at login, before anyone opens it.
    if (widget.visit == null) _offerAfterFrame();
  }

  @override
  void didUpdateWidget(ServiceNowHubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visit != oldWidget.visit) _offerAfterFrame();
  }

  void _offerAfterFrame() => WidgetsBinding.instance
      .addPostFrameCallback((_) => _offerNotifications());

  Future<void> _offerNotifications() async {
    final settings = widget.session.settings;
    if (_notificationsOffered || await settings.getNotificationsEnabled()) {
      return;
    }
    if (!mounted) return;
    _notificationsOffered = true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Activer les notifications ?'),
        content: const Text(
          'Soyez prévenu quand une demande est acceptée, quand le prestataire '
          'arrive et quand le travail est terminé.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Plus tard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Activer'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    final granted = await NotificationService.instance.ensurePermission();
    if (granted) await settings.setNotificationsEnabled(true);
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => DemandeFormScreen(session: widget.session),
      ),
    );
    if (created == true && mounted) setState(() => _epoch++);
  }

  Widget _prestataire() {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ServiceNow'),
          actions: [
            IconButton(
              tooltip: 'Mes disponibilités',
              icon: const Icon(Icons.event_available_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      PrestataireAvailabilityScreen(session: widget.session),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Mon profil de prestataire',
              icon: const Icon(Icons.tune),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      PrestataireProfileScreen(session: widget.session),
                ),
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.inbox_outlined), text: 'Disponibles'),
              Tab(icon: Icon(Icons.handyman_outlined), text: 'Mes interventions'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            DemandeListView(
              session: widget.session,
              load: _api.availableDemandes,
              emptyIcon: Icons.inbox_outlined,
              emptyTitle: 'Aucune demande disponible',
              emptyMessage: 'Les nouvelles demandes des clients apparaîtront ici.',
            ),
            DemandeListView(
              session: widget.session,
              load: _api.myInterventions,
              emptyIcon: Icons.handyman_outlined,
              emptyTitle: 'Aucune intervention',
              emptyMessage:
                  'Acceptez une demande pour la retrouver dans cette liste.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _client() {
    return Scaffold(
      appBar: AppBar(title: const Text('ServiceNow')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle demande'),
      ),
      body: DemandeListView(
        key: ValueKey('mes-demandes-$_epoch'),
        session: widget.session,
        load: _api.myDemandes,
        emptyIcon: Icons.home_repair_service_outlined,
        emptyTitle: 'Aucune demande',
        emptyMessage:
            'Décrivez votre besoin pour trouver un prestataire près de chez vous.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      widget.session.user?.role == UserRole.prestataire
          ? _prestataire()
          : _client();
}
