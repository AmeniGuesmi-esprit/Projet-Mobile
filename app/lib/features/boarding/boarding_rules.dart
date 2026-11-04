/// Same window as the server (ReservationService): boarding opens 30 minutes
/// before departure and closes 60 minutes after.
const Duration boardingOpensBefore = Duration(minutes: 30);
const Duration boardingClosesAfter = Duration(minutes: 60);

bool isBoardingWindowOpen(DateTime departure, {DateTime? now}) {
  final t = now ?? DateTime.now();
  return !t.isBefore(departure.subtract(boardingOpensBefore)) &&
      !t.isAfter(departure.add(boardingClosesAfter));
}
