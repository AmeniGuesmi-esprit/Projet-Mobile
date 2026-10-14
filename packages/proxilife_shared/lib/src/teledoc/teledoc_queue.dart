import 'teledoc_enums.dart';

/// Minimal view of a waiting request, enough to order the queue.
class TeledocQueueEntry {
  const TeledocQueueEntry({
    required this.id,
    required this.urgence,
    required this.creeLe,
  });

  final int id;
  final TeledocUrgency urgence;
  final DateTime creeLe;
}

/// Position and estimated wait of one request in the queue.
class TeledocQueuePlace {
  const TeledocQueuePlace(this.position, this.waitMinutes);

  /// 1 = head of the queue.
  final int position;
  final int waitMinutes;
}

/// Virtual waiting-queue maths (pure functions, unit-tested).
///
/// - Order: urgency (high first), then creation date, then id.
/// - Wait: `⌊(position − 1) / doctors⌋ × averageMinutes`, so the first
///   `doctors` patients wait ≈ 0 min.
class TeledocQueue {
  const TeledocQueue._();

  /// Fallback consultation length when there is no history yet.
  static const int defaultDurationMinutes = 15;
  static const int minDurationMinutes = 5;
  static const int maxDurationMinutes = 60;

  /// How many recent consultations feed the average.
  static const int durationSampleSize = 20;

  /// Position at or below which the patient is told "c'est bientôt votre tour".
  static const int soonThreshold = 2;

  static int compare(TeledocQueueEntry a, TeledocQueueEntry b) {
    final byUrgency = b.urgence.priority.compareTo(a.urgence.priority);
    if (byUrgency != 0) return byUrgency;
    final byDate = a.creeLe.compareTo(b.creeLe);
    if (byDate != 0) return byDate;
    return a.id.compareTo(b.id);
  }

  /// Returns a new list sorted in queue order.
  static List<TeledocQueueEntry> order(Iterable<TeledocQueueEntry> entries) =>
      entries.toList()..sort(compare);

  static int estimateWaitMinutes({
    required int position,
    required int doctors,
    required int averageMinutes,
  }) {
    if (position < 1) throw ArgumentError.value(position, 'position');
    final available = doctors < 1 ? 1 : doctors;
    return ((position - 1) ~/ available) * averageMinutes;
  }

  /// Average length (rounded minutes) of past consultations, clamped to
  /// [[minDurationMinutes], [maxDurationMinutes]]. Negative durations (bad
  /// clocks) are ignored.
  static int averageDurationMinutes(Iterable<Duration> durations) {
    final valid = durations.where((d) => !d.isNegative).toList();
    if (valid.isEmpty) return defaultDurationMinutes;
    final totalSeconds =
        valid.fold<int>(0, (sum, d) => sum + d.inSeconds);
    final average = (totalSeconds / valid.length / 60).round();
    return average.clamp(minDurationMinutes, maxDurationMinutes);
  }

  /// Computes position + wait for every waiting request, keyed by id.
  static Map<int, TeledocQueuePlace> places(
    Iterable<TeledocQueueEntry> entries, {
    required int doctors,
    required int averageMinutes,
  }) {
    final ordered = order(entries);
    return {
      for (var i = 0; i < ordered.length; i++)
        ordered[i].id: TeledocQueuePlace(
          i + 1,
          estimateWaitMinutes(
            position: i + 1,
            doctors: doctors,
            averageMinutes: averageMinutes,
          ),
        ),
    };
  }

  static bool isSoon(int position) => position <= soonThreshold;
}
