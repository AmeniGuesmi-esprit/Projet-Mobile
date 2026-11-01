import 'package:flutter_test/flutter_test.dart';
import 'package:proxilife/features/payment/recent_beneficiaries.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(RecentBeneficiaries, SharedPreferences)> makeStore(
      [Map<String, Object> initial = const {}]) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await SharedPreferences.getInstance();
    return (RecentBeneficiaries(prefs: prefs), prefs);
  }

  test('remember inserts most recent first and de-duplicates', () async {
    final (recents, _) = await makeStore();

    await recents.remember(email: 'ameni@test.tn', name: 'Ameni Guesmi');
    await recents.remember(email: 'pro@test.tn', name: 'Proxi Driver');
    await recents.remember(email: 'AMENI@test.tn', name: 'Ameni G.');

    final entries = await recents.load();
    expect(entries.map((e) => e.email),
        ['ameni@test.tn', 'pro@test.tn']);
    expect(entries.first.name, 'Ameni G.');
  });

  test('list is capped at maxEntries and survives a new instance', () async {
    final (recents, prefs) = await makeStore();
    for (var i = 1; i <= 7; i++) {
      await recents.remember(email: 'user$i@test.tn');
    }
    expect((await recents.load()), hasLength(RecentBeneficiaries.maxEntries));
    expect((await recents.load()).first.email, 'user7@test.tn');

    // A fresh instance over the same store sees the same history.
    final reloaded = RecentBeneficiaries(prefs: prefs);
    expect(await reloaded.load(), hasLength(RecentBeneficiaries.maxEntries));
  });

  test('display falls back to the e-mail when no name is stored', () async {
    final (recents, _) = await makeStore();
    await recents.remember(email: 'noname@test.tn');
    await recents.remember(email: 'named@test.tn', name: 'Ameni G.');

    final entries = await recents.load();
    expect(entries.firstWhere((e) => e.email == 'noname@test.tn').display,
        'noname@test.tn');
    expect(entries.firstWhere((e) => e.email == 'named@test.tn').display,
        'Ameni G.');
  });
}
