import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/empty_state.dart';
import 'coach_my_bookings_screen.dart';
import 'coach_notifications_screen.dart';
import 'coach_search_screen.dart';
import 'coach_sessions_screen.dart';

/// Entry of the CoachProche module: coaches get their space; every other role
/// books sessions as a client (like FoodSave's client side). Pushed with
/// `pushCoach`, so the whole module uses the violet theme.
class CoachHomeScreen extends StatelessWidget {
  const CoachHomeScreen({
    super.key,
    required this.session,
    this.embedded = false,
  });

  final SessionController session;

  /// True when shown as a tab of the main bottom bar (no own bottom bar).
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return switch (session.user?.role) {
      null => Scaffold(
          appBar: AppBar(title: const Text('CoachProche')),
          body: const EmptyState(
            icon: Icons.fitness_center_outlined,
            title: 'Connexion requise',
            message: 'Connectez-vous pour utiliser le coaching sportif.',
            color: AppColors.moduleCoachProche,
          ),
        ),
      UserRole.coach => CoachSessionsScreen(session: session),
      _ => _ClientHome(session: session, embedded: embedded),
    };
  }
}

/// Client space: « Séances » (search) and « Mes réservations ».
class _ClientHome extends StatefulWidget {
  const _ClientHome({required this.session, required this.embedded});

  final SessionController session;
  final bool embedded;

  @override
  State<_ClientHome> createState() => _ClientHomeState();
}

class _ClientHomeState extends State<_ClientHome> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      // Already inside the main bottom bar: use top tabs instead of a second
      // bottom bar.
      return DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('CoachProche'),
            actions: [CoachBellButton(session: widget.session)],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Séances'),
                Tab(text: 'Mes réservations'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              CoachSearchScreen(session: widget.session),
              CoachMyBookingsScreen(session: widget.session),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_index == 0 ? 'Séances de sport' : 'Mes réservations'),
        actions: [CoachBellButton(session: widget.session)],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          CoachSearchScreen(session: widget.session),
          CoachMyBookingsScreen(session: widget.session),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.search),
            label: 'Séances',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_available_outlined),
            selectedIcon: Icon(Icons.event_available),
            label: 'Mes réservations',
          ),
        ],
      ),
    );
  }
}
