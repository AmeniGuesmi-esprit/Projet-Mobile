import 'package:flutter/material.dart';

import '../../core/session/session_controller.dart';
import '../foodsave/platform/foodsave_hub_screen.dart';
import '../foodsave/platform/foodsave_notification_poller.dart';
import '../payment/payments_screen.dart';
import '../profile/profile_screen.dart';
import '../service_now/service_now_hub_screen.dart';
import '../teledoc/presentation/screens/teledoc_home_screen.dart';
import '../trips/covoiturage_hub_screen.dart';
import 'home_screen.dart';

/// One bottom-navigation tab. Lists that must stay fresh are refreshed by
/// the tab itself (e.g. [CovoiturageHubScreen] uses the visit count).
class _Tab {
  const _Tab({required this.id, required this.page, required this.destination});

  final String id;
  final Widget page;
  final NavigationDestination destination;
}

/// Root scaffold with the bottom navigation.
///  Accueil · Paiements · FoodSave · Covoiturage · TeleDoc · ServiceNow · Profil, for every
///  role. Covoiturage: Mes trajets · Demandes for drivers, Rechercher ·
///  Réservations for everyone else ([CovoiturageHubScreen]). TeleDoc: the
///  doctor space for médecins, the patient space for everyone else.
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.session});

  final SessionController session;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  /// Times each tab was opened (lets the Covoiturage hub refresh its list).
  final Map<String, int> _visits = {};

  /// Selects tab [i]; counts a visit when it changes.
  void _select(List<_Tab> tabs, int i, int current) {
    setState(() {
      if (i != current) {
        final id = tabs[i].id;
        _visits[id] = (_visits[id] ?? 0) + 1;
      }
      _index = i;
    });
  }

  /// Opens the tab with this id (used by the home-screen shortcuts).
  void _openTab(String id) {
    final tabs = _tabs();
    final i = tabs.indexWhere((t) => t.id == id);
    if (i >= 0) _select(tabs, i, _index.clamp(0, tabs.length - 1));
  }

  List<_Tab> _tabs() {
    final role = widget.session.user?.role;
    final session = widget.session;
    return [
      _Tab(
        id: 'home',
        page: HomeScreen(session: session, onOpenTab: _openTab),
        destination: const NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Accueil',
        ),
      ),
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
      if (CovoiturageHubScreen.availableFor(role))
        _Tab(
          id: 'covoiturage',
          page: CovoiturageHubScreen(
            session: session,
            visit: _visits['covoiturage'] ?? 0,
          ),
          destination: const NavigationDestination(
            icon: Icon(Icons.directions_car_outlined),
            selectedIcon: Icon(Icons.directions_car),
            label: 'EcoRoute',
          ),
        ),
      _Tab(
        id: 'teledoc',
        page: TeledocHomeScreen(session: session),
        destination: const NavigationDestination(
          icon: Icon(Icons.medical_services_outlined),
          selectedIcon: Icon(Icons.medical_services),
          label: 'TeleDoc',
        ),
      ),
      _Tab(
        id: 'servicenow',
        page: ServiceNowHubScreen(
          session: session,
          visit: _visits['servicenow'] ?? 0,
        ),
        destination: const NavigationDestination(
          icon: Icon(Icons.build_outlined),
          selectedIcon: Icon(Icons.build),
          label: 'ServiceNow',
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
                KeyedSubtree(key: ValueKey(tab.id), child: tab.page),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) => _select(tabs, i, index),
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
      // Same fork & knife as the FoodSave service badge.
      child: Icon(selected ? Icons.restaurant : Icons.restaurant_outlined),
    );
  }
}
