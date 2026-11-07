import 'package:shelf_router/shelf_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../repositories/user_repository.dart';
import '../services/payment_service.dart';
import 'coach_routes.dart';
import 'coach_service.dart';

export 'coach_routes.dart' show startCoachJobs;
export 'coach_service.dart' show CoachService;

/// Builds the CoachProche service from the shared server pieces. Used by
/// `bin/server.dart` (which also starts the reminder job) and by `buildApp`
/// when no service is injected (tests).
CoachService buildCoachService(
  Database db,
  UserRepository users,
  PaymentService payments, {
  DateTime Function()? clock,
}) =>
    CoachService(db: db, users: users, payments: payments, clock: clock);

/// All CoachProche routes (single `mount` line in `app.dart`).
Router buildCoachModule(CoachService service) => buildCoachRoutes(service);
