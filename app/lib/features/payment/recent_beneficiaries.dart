import 'package:shared_preferences/shared_preferences.dart';

/// One remembered beneficiary (last successful payments).
class RecentBeneficiary {
  const RecentBeneficiary({required this.email, this.name});

  final String email;
  final String? name;

  String get display => name == null || name!.isEmpty ? email : name!;
}

/// Remembers the most recent payment beneficiaries (most recent first,
/// at most [maxEntries]), shared across sessions via shared_preferences.
class RecentBeneficiaries {
  RecentBeneficiaries({this._prefs});

  static const String _key = 'recent_beneficiaries_v1';
  static const int maxEntries = 5;

  final SharedPreferences? _prefs;

  Future<SharedPreferences> get _store async =>
      _prefs ?? SharedPreferences.getInstance();

  Future<List<RecentBeneficiary>> load() async {
    final store = await _store;
    final raw = store.getStringList(_key) ?? const <String>[];
    return raw.map(_decode).whereType<RecentBeneficiary>().toList();
  }

  /// Records [email] (and optional display [name]) as the most recent
  /// beneficiary, de-duplicating and capping the list.
  Future<List<RecentBeneficiary>> remember({
    required String email,
    String? name,
  }) async {
    final normalized = email.trim().toLowerCase();
    final entries = await load();
    entries.removeWhere((e) => e.email == normalized);
    entries.insert(
        0,
        RecentBeneficiary(
            email: normalized,
            name: (name == null || name.trim().isEmpty)
                ? null
                : name.trim()));
    if (entries.length > maxEntries) {
      entries.removeRange(maxEntries, entries.length);
    }
    final store = await _store;
    await store.setStringList(_key, entries.map(_encode).toList());
    return entries;
  }

  static String _encode(RecentBeneficiary e) => '${e.email}|${e.name ?? ''}';

  static RecentBeneficiary? _decode(String raw) {
    final sep = raw.indexOf('|');
    if (sep <= 0) return null;
    final email = raw.substring(0, sep);
    final name = raw.substring(sep + 1);
    return RecentBeneficiary(
        email: email, name: name.isEmpty ? null : name);
  }
}
