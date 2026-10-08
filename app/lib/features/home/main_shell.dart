import 'package:flutter/material.dart';

import '../../core/session/session_controller.dart';
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
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}
