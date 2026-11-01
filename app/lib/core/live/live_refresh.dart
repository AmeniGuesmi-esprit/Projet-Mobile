import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Keeps a screen up to date without pull-to-refresh.
///
/// Calls [liveRefresh] every [LiveRefreshConfig.interval] while the screen
/// is the visible route and the app is in the foreground, and right away
/// when the app comes back to the foreground. Implementations fetch the
/// data in the background and swap it in with [liveFuture], so the content
/// changes in place (no loader, no flicker). Failures keep the current data.
mixin LiveRefresh<T extends StatefulWidget> on State<T> {
  Timer? _liveTimer;
  _LiveLifecycleObserver? _liveObserver;
  bool _liveBusy = false;

  /// Silent reload of the screen's data.
  Future<void> liveRefresh();

  @override
  void initState() {
    super.initState();
    if (!LiveRefreshConfig.enabled) return;
    _liveObserver = _LiveLifecycleObserver(_liveTick);
    WidgetsBinding.instance.addObserver(_liveObserver!);
    _liveTimer =
        Timer.periodic(LiveRefreshConfig.interval, (_) => _liveTick());
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    final observer = _liveObserver;
    if (observer != null) WidgetsBinding.instance.removeObserver(observer);
    super.dispose();
  }

  Future<void> _liveTick() async {
    if (!mounted || _liveBusy) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return; // covered by another page
    _liveBusy = true;
    try {
      await liveRefresh();
    } catch (_) {
      // Offline / server error: keep what is on screen, retry next tick.
    } finally {
      _liveBusy = false;
    }
  }
}

/// An already-completed future: a FutureBuilder given it renders the new
/// data in the same frame (no "waiting" state, hence no loader flash).
Future<D> liveFuture<D>(D data) => SynchronousFuture<D>(data);

/// Global settings of [LiveRefresh].
class LiveRefreshConfig {
  const LiveRefreshConfig._();

  /// How often visible screens re-query the server.
  static Duration interval = const Duration(seconds: 10);

  /// Widget tests turn live refresh off (no periodic timers).
  @visibleForTesting
  static bool enabled = true;
}

class _LiveLifecycleObserver with WidgetsBindingObserver {
  _LiveLifecycleObserver(this.onResumed);

  final VoidCallback onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }
}
