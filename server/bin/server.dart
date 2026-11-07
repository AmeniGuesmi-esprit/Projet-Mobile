import 'dart:io';

import 'package:proxilife_server/src/app.dart';
import 'package:proxilife_server/src/coach/coach_module.dart';
import 'package:proxilife_server/src/db/database.dart';
import 'package:proxilife_server/src/config/server_config.dart';
import 'package:proxilife_server/src/email/email_sender.dart';
import 'package:proxilife_server/src/foodsave/foodsave_context.dart';
import 'package:proxilife_server/src/foodsave/foodsave_module.dart';
import 'package:proxilife_server/src/foodsave/services/reverse_geocoder.dart';
import 'package:proxilife_server/src/foodsave/services/route_planner.dart';
import 'package:proxilife_server/src/repositories/payment_method_repository.dart';
import 'package:proxilife_server/src/repositories/transaction_repository.dart';
import 'package:proxilife_server/src/repositories/user_repository.dart';
import 'package:proxilife_server/src/services/payment_service.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main(List<String> args) async {
  final config = await ServerConfig.load();
  stdout.writeln('ProxiLife server starting...');
  stdout.writeln('DB       : ${config.dbPath}');
  stdout.writeln(
      'E-mail   : ${config.emailConsoleMode ? 'console (offline)' : 'smtp'}');

  final database = await AppDatabase.open(config.dbPath);
  final users = UserRepository(database.db);
  final emailSender = createEmailSender(config);
  final ttlMinutes =
      int.tryParse(Platform.environment['FOODSAVE_QR_TTL_MINUTES'] ?? '') ?? 30;
  final payments = PaymentService(
    db: database.db,
    users: users,
    methods: PaymentMethodRepository(database.db),
    transactions: TransactionRepository(database.db),
  );
  final foodSave = FoodSaveContext(
    db: database.db,
    users: users,
    payments: payments,
    uploadsDir: 'uploads',
    qrTtl: Duration(minutes: ttlMinutes),
    mailer: switch (emailSender) { ReservationMailer m => m, _ => null },
    geocoder: NominatimGeocoder(),
    routePlanner: OsrmRoutePlanner(),
  );
  final coach = buildCoachService(database.db, users, payments);
  final handler = buildApp(database, config,
      emailSender: emailSender, foodSave: foodSave, coach: coach);
  final foodSaveJobs = startFoodSaveJobs(foodSave);
  final coachJobs = startCoachJobs(coach);
  stdout.writeln('CoachProche : rappels avant séance, job toutes les 60 s');
  stdout.writeln('FoodSave : QR $ttlMinutes min, expiry job every 30 s');

  final server = await shelf_io.serve(
    handler,
    InternetAddress.anyIPv4,
    config.port,
  );
  stdout.writeln(
      'Listening on http://${server.address.address}:${server.port}');
  stdout.writeln('Emulator URL: http://10.0.2.2:${server.port}');

  ProcessSignal.sigint.watch().listen((_) async {
    foodSaveJobs.cancel();
    coachJobs.cancel();
    await database.close();
    await server.close(force: true);
    exit(0);
  });
}
