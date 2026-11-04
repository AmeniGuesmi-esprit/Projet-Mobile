import 'dart:io';

import 'package:proxilife_server/src/config/server_config.dart';
import 'package:proxilife_server/src/db/database.dart';
import 'package:proxilife_server/src/routes/teledoc_routes.dart';

/// Deletes TeleDoc symptom photos that no request of THIS database
/// references any more (CONCEPTION.md, D43). Run it on purpose, against the
/// database that owns `uploads/teledoc`: `dart run bin/teledoc_purge.dart`.
Future<void> main() async {
  final config = await ServerConfig.load();
  stdout.writeln('DB       : ${config.dbPath}');
  final database = await AppDatabase.open(config.dbPath);
  stdout.writeln(await purgeTeledocOrphanPhotos(database.db));
  await database.close();
}
