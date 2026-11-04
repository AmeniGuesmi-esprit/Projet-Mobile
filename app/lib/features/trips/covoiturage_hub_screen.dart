import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/session/session_controller.dart';
import '../reservations/my_reservations_screen.dart';
import '../reservations/received_requests_screen.dart';
import '../search/search_trips_screen.dart';
import 'my_trips_screen.dart';

/// Single "Covoiturage" bottom tab (like FoodSave) grouping the two
/// carpooling screens of the user's role under top tabs:
///  - conducteur    : Mes trajets · Demandes
///  - every other role (client, commerçant, médecin, coach, admin) rides as
///    a passenger : Rechercher · Réservations
///
/// Lists (Réservations, Mes trajets, Demandes) are rebuilt each time they
/// are shown, so they are always fresh; the search keeps its state.
class CovoiturageHubScreen extends StatefulWidget {
  const CovoiturageHubScreen({
    super.key,
    required this.session,
    this.visit = 0,
  });

  final SessionController session;

  /// Incremented by the shell each time the "Covoiturage" tab is opened.
  final int visit;

  /// Every signed-in user: drivers publish, everyone else can book (the
  /// server only restricts publishing to drivers).
  static bool availableFor(UserRole? role) => role != null;

  @override
  State<CovoiturageHubScreen> createState() => _CovoiturageHubScreenState();
}

class _SubTab {
  const _SubTab(this.label, this.icon, this.build, {this.reload = false});

  final String label;
  final IconData icon;
  final Widget Function() build;

  /// Rebuilt each time it is shown (fresh list).
  final bool reload;
}

class _CovoiturageHubScreenState extends State<CovoiturageHubScreen>
    with SingleTickerProviderStateMixin {
  late final List<_SubTab> _tabs = _tabsFor(widget.session);
  late final TabController _controller =
      TabController(length: _tabs.length, vsync: this)
        ..addListener(_onTabChanged);
  final Map<int, int> _epochs = {};

  List<_SubTab> _tabsFor(SessionController session) =>
      session.user?.role == UserRole.conducteur
          ? [
              _SubTab('Mes trajets', Icons.directions_car_outlined,
                  () => MyTripsScreen(session: session, embedded: true),
                  reload: true),
              _SubTab('Demandes', Icons.inbox_outlined,
                  () => ReceivedRequestsScreen(session: session, embedded: true),
                  reload: true),
            ]
          : [
              _SubTab('Rechercher', Icons.search,
                  () => SearchTripsScreen(session: session, embedded: true)),
              _SubTab('Réservations', Icons.event_seat_outlined,
                  () => MyReservationsScreen(session: session, embedded: true),
                  reload: true),
            ];

  void _reload(int index) {
    if (_tabs[index].reload) {
      _epochs[index] = (_epochs[index] ?? 0) + 1;
    }
  }

  void _onTabChanged() {
    if (_controller.indexIsChanging) return;
    setState(() => _reload(_controller.index));
  }

  @override
  void didUpdateWidget(CovoiturageHubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Back on the "Covoiturage" tab: refresh the visible list.
    if (widget.visit != oldWidget.visit) _reload(_controller.index);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('EcoRoute'),
        bottom: TabBar(
          controller: _controller,
          tabs: [
            for (final tab in _tabs)
              Tab(icon: Icon(tab.icon), text: tab.label, height: 64),
          ],
        ),
      ),
      body: TabBarView(
        controller: _controller,
        children: [
          for (var i = 0; i < _tabs.length; i++)
            KeyedSubtree(
              key: ValueKey('covoiturage-$i-${_epochs[i] ?? 0}'),
              child: _tabs[i].build(),
            ),
        ],
      ),
    );
  }
}
