import 'package:flutter/material.dart';

import '../../core/session/session_controller.dart';
import '../foodsave/platform/foodsave_hub_screen.dart';
import '../foodsave/platform/foodsave_notification_poller.dart';
import '../payment/payments_screen.dart';
import '../profile/profile_screen.dart';
import 'home_screen.dart';

/// Root scaffold with the bottom navigation.
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.session});

  final SessionController session;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomeScreen(session: widget.session),
      PaymentsScreen(session: widget.session),
      FoodSaveHubScreen(session: widget.session),
      ProfileScreen(session: widget.session),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Paiements',
          ),
          NavigationDestination(
            icon: _FoodSaveTabIcon(selected: false),
            selectedIcon: _FoodSaveTabIcon(selected: true),
            label: 'FoodSave',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
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
