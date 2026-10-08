import 'dart:io';

import 'package:proxilife_server/src/app.dart';
import 'package:proxilife_server/src/db/database.dart';
import 'package:proxilife_server/src/config/server_config.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main(List<String> args) async {
  final config = await ServerConfig.load();
  stdout.writeln('ProxiLife server starting...');
  stdout.writeln('DB       : ${config.dbPath}');
  stdout.writeln(
      'E-mail   : ${config.emailConsoleMode ? 'console (offline)' : 'smtp'}');

  final database = await AppDatabase.open(config.dbPath);
  final handler = buildApp(database, config);

  final server = await shelf_io.serve(
    handler,
    InternetAddress.loopbackIPv4,
    config.port,
  );
  stdout.writeln(
      'Listening on http://${server.address.address}:${server.port}');
  stdout.writeln('Emulator URL: http://10.0.2.2:${server.port}');

  ProcessSignal.sigint.watch().listen((_) async {
    await database.close();
    await server.close(force: true);
    exit(0);
  });
}
