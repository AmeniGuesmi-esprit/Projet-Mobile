/// Format of a teleconsultation call room (CONCEPTION.md, D34–D35).
///
/// The server draws 16 secure random bytes per consultation: knowing the
/// room name is what gives access to the call, so it must not be guessable.
/// The app re-checks the format before building a URL with it.
abstract final class TeledocCallRoom {
  static const String prefix = 'ProxiLifeTeleDoc';

  static final RegExp _pattern = RegExp(r'^ProxiLifeTeleDoc[0-9a-f]{32}$');

  static bool isValid(String? room) => room != null && _pattern.hasMatch(room);
}
