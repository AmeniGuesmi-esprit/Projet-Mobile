import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../core/api/api_client.dart';
import '../../domain/teledoc_queue_tracker.dart';
import '../../domain/teledoc_repository.dart';

/// State of the patient's virtual waiting queue, refreshed by polling.
///
/// Polling every [interval] (5 s, CONCEPTION.md §5.2) while the waiting
/// screen exists; it stops by itself once the request leaves the queue
/// (consultation started, cancelled or finished). A network error keeps the
/// last known status on screen and polling continues.
class TeledocQueueController extends ChangeNotifier {
  TeledocQueueController({
    required this.repository,
    required this.requestId,
    required this.notifier,
    this.interval = const Duration(seconds: 5),
  });

  final TeledocRepository repository;
  final int requestId;
  final TeledocQueueNotifier notifier;
  final Duration interval;

  final TeledocQueueTracker _tracker = TeledocQueueTracker();
  Timer? _timer;
  bool _inFlight = false;
  bool _disposed = false;

  TeledocQueueStatusDto? status;

  /// Last error message (French), `null` when the last refresh succeeded.
  String? error;
  DateTime? lastUpdate;

  bool get isPolling => _timer != null;
  bool get isWaiting => status?.statut == TeledocRequestStatus.enAttente;

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(interval, (_) => refresh());
    refresh();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// One poll. Overlapping calls are skipped (slow network + 5 s timer).
  Future<void> refresh() async {
    if (_inFlight || _disposed) return;
    _inFlight = true;
    try {
      final next = await repository.queueStatus(requestId);
      if (_disposed) return;
      status = next;
      error = null;
      lastUpdate = DateTime.now();
      for (final event in _tracker.update(next)) {
        await notifier.notify(event, next);
      }
      if (next.statut != TeledocRequestStatus.enAttente) stop();
    } on ApiException catch (e) {
      error = e.message;
      // The request is gone or no longer ours: polling is pointless.
      if (e.statusCode == 404 || e.statusCode == 403) stop();
    } finally {
      _inFlight = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
