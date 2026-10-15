import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:proxilife_server/src/db/database.dart';
import 'package:proxilife_server/src/routes/teledoc_routes.dart';
import 'package:proxilife_server/src/services/teledoc_photo_store.dart';
import 'package:test/test.dart';

import 'teledoc_test_support.dart';

void main() {
  late Directory dir;
  final old = DateTime.now().subtract(const Duration(days: 2));

  setUp(() async => dir = await Directory.systemTemp.createTemp('purge'));
  tearDown(() => dir.delete(recursive: true));

  Future<String> file(String name, {DateTime? modified}) async {
    final f = File(p.join(dir.path, name));
    await f.writeAsBytes([1, 2, 3]);
    if (modified != null) await f.setLastModified(modified);
    return name;
  }

  List<String> remaining() =>
      dir.listSync().map((f) => p.basename(f.path)).toList()..sort();

  test('ne supprime que les photos orphelines anciennes au bon format',
      () async {
    final kept = await file('${'a' * 32}.jpg', modified: old);
    final orphan = await file('${'b' * 32}.png', modified: old);
    final recent = await file('${'c' * 32}.jpg'); // being saved right now
    final foreign = await file('notes.txt', modified: old);

    final deleted = await TeledocPhotoStore(dir.path).purgeOrphans({kept});

    expect(deleted, 1);
    expect(remaining(), isNot(contains(orphan)));
    expect(remaining(), containsAll([kept, recent, foreign]));
  });

  test('dossier absent : rien à faire', () async {
    final store = TeledocPhotoStore(p.join(dir.path, 'absent'));
    expect(await store.purgeOrphans({}), 0);
  });

  test('compte supprimé (cascade) : sa photo est nettoyée au démarrage',
      () async {
    final database = await AppDatabase.inMemory();
    addTearDown(database.close);
    final db = database.db;
    final patient = await insertTestUser(db, 'p@test.tn', 'client');
    final other = await insertTestUser(db, 'o@test.tn', 'client');
    final mine = await file('${'d' * 32}.jpg', modified: old);
    final theirs = await file('${'e' * 32}.jpg', modified: old);
    for (final (owner, photo) in [(patient, mine), (other, theirs)]) {
      final id = await insertTestRequest(db, owner);
      await db.update('teledoc_demande', {'photo_symptome': photo},
          where: 'id = ?', whereArgs: [id]);
    }

    await db.delete('utilisateur', where: 'id = ?', whereArgs: [patient]);
    final log = await purgeTeledocOrphanPhotos(db, uploadsDir: dir.path);

    expect(log, contains('1 photo(s)'));
    expect(remaining(), [theirs]);
  });
}
