import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/session/session_controller.dart';
import '../foodsave/platform/foodsave_hub_screen.dart';
import '../foodsave/platform/foodsave_notification_poller.dart';
import '../payment/payments_screen.dart';
import '../profile/profile_screen.dart';
import '../reservations/my_reservations_screen.dart';
import '../reservations/received_requests_screen.dart';
import '../search/search_trips_screen.dart';
import '../trips/my_trips_screen.dart';
import 'home_screen.dart';

/// One bottom-navigation tab. Tabs flagged [reloadOnSelect] are rebuilt each
/// time they are opened, so their lists are always fresh (a reservation sent
/// from the search tab shows up in "Réservations" right away).
class _Tab {
  const _Tab({
    required this.id,
    required this.page,
    required this.destination,
    this.reloadOnSelect = false,
  });

  final String id;
  final Widget page;
  final NavigationDestination destination;
  final bool reloadOnSelect;
}

/// Root scaffold with the bottom navigation.
///  - conducteur : Accueil, Mes trajets, Demandes, Paiements, FoodSave, Profil
///  - client (passager) : Accueil, Rechercher, Réservations, Paiements, FoodSave, Profil
///  - other roles : Accueil, Paiements, FoodSave, Profil
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.session});

  final SessionController session;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  final Map<String, int> _epochs = {};

  List<_Tab> _tabs() {
    final role = widget.session.user?.role;
    final session = widget.session;
    return [
      _Tab(
        id: 'home',
        page: HomeScreen(session: session),
        destination: const NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Accueil',
        ),
      ),
      if (role == UserRole.conducteur) ...[
        _Tab(
          id: 'trips',
          page: MyTripsScreen(session: session),
          reloadOnSelect: true,
          destination: const NavigationDestination(
            icon: Icon(Icons.directions_car_outlined),
            selectedIcon: Icon(Icons.directions_car),
            label: 'Mes trajets',
          ),
        ),
        _Tab(
          id: 'requests',
          page: ReceivedRequestsScreen(session: session),
          reloadOnSelect: true,
          destination: const NavigationDestination(
            icon: Icon(Icons.inbox_outlined),
            selectedIcon: Icon(Icons.inbox),
            label: 'Demandes',
          ),
        ),
      ],
      if (role == UserRole.client) ...[
        _Tab(
          id: 'search',
          page: SearchTripsScreen(session: session),
          destination: const NavigationDestination(
            icon: Icon(Icons.search),
            selectedIcon: Icon(Icons.search),
            label: 'Rechercher',
          ),
        ),
        _Tab(
          id: 'reservations',
          page: MyReservationsScreen(session: session),
          reloadOnSelect: true,
          destination: const NavigationDestination(
            icon: Icon(Icons.event_seat_outlined),
            selectedIcon: Icon(Icons.event_seat),
            label: 'Réservations',
          ),
        ),
      ],
      _Tab(
        id: 'payments',
        page: PaymentsScreen(session: session),
        destination: const NavigationDestination(
          icon: Icon(Icons.account_balance_wallet_outlined),
          selectedIcon: Icon(Icons.account_balance_wallet),
          label: 'Paiements',
        ),
      ),
      _Tab(
        id: 'foodsave',
        page: FoodSaveHubScreen(session: session),
        destination: const NavigationDestination(
          icon: _FoodSaveTabIcon(selected: false),
          selectedIcon: _FoodSaveTabIcon(selected: true),
          label: 'FoodSave',
        ),
      ),
      _Tab(
        id: 'profile',
        page: ProfileScreen(session: session),
        destination: const NavigationDestination(
          icon: Icon(Icons.person_outline),
          selectedIcon: Icon(Icons.person),
          label: 'Profil',
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final tabs = _tabs();
        final index = _index.clamp(0, tabs.length - 1);

        return Scaffold(
          body: IndexedStack(
            index: index,
            children: [
              for (final tab in tabs)
                KeyedSubtree(
                  key: ValueKey('${tab.id}-${_epochs[tab.id] ?? 0}'),
                  child: tab.page,
                ),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => setState(() {
              final tab = tabs[i];
              if (tab.reloadOnSelect && i != index) {
                _epochs[tab.id] = (_epochs[tab.id] ?? 0) + 1;
              }
              _index = i;
            }),
            destinations: [for (final tab in tabs) tab.destination],
          ),
        );
      },
    );
  }
}

/// FoodSave tab icon with the unread-notifications badge.
class _FoodSaveTabIcon extends StatelessWidget {
  const _FoodSaveTabIcon({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: FoodSaveNotificationPoller.instance.unread,
      builder: (context, count, child) => Badge(
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '99+' : '$count'),
        child: child,
      ),
      child: Icon(selected ? Icons.eco : Icons.eco_outlined),
    );
  }
}