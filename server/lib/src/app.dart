import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth/auth_middleware.dart';
import 'auth/session_service.dart';
import 'coach/coach_module.dart';
import 'config/server_config.dart';
import 'db/database.dart';
import 'email/email_sender.dart';
import 'foodsave/foodsave_context.dart';
import 'foodsave/foodsave_module.dart';
import 'repositories/payment_method_repository.dart';
import 'repositories/reservation_repository.dart';
import 'repositories/service_now_repository.dart';
import 'repositories/transaction_repository.dart';
import 'repositories/trip_repository.dart';
import 'repositories/user_repository.dart';
import 'repositories/vehicle_repository.dart';
import 'repositories/verification_repository.dart';
import 'routes/auth_routes.dart';
import 'routes/payment_routes.dart';
import 'routes/reservation_routes.dart';
import 'routes/service_now_routes.dart';
import 'routes/teledoc_routes.dart';
import 'routes/trip_routes.dart';
import 'routes/user_routes.dart';
import 'services/auth_service.dart';
import 'services/payment_assistant_service.dart';
import 'services/payment_service.dart';
import 'services/reservation_service.dart';
import 'services/service_now_geocoder.dart';
import 'services/service_now_service.dart';
import 'services/teledoc_photo_store.dart';
import 'foodsave/services/route_planner.dart';
import 'services/trip_service.dart';

/// Wires repositories, services and routes into a single shelf [Handler].
/// Reusable by the real server (`bin/server.dart`) and by integration tests
/// (in-memory database + fake e-mail sender).
Handler buildApp(
  AppDatabase database,
  ServerConfig config, {
  EmailSender? emailSender,
  bool logRequestsMiddleware = true,
  FoodSaveContext? foodSave,
  CoachService? coach,
  String uploadsDir = 'uploads',
  AddressGeocoder? serviceNowGeocoder,
  RoutePlanner? serviceNowRoutes,
}) {
  final users = UserRepository(database.db);
  final verification = VerificationRepository(database.db);
  final sessions = SessionService(database.db, users);
  final sender = emailSender ?? createEmailSender(config);
  final auth = AuthService(
    users: users,
    verification: verification,
    sessions: sessions,
    email: sender,
  );
  final transactions = TransactionRepository(database.db);
  final payments = PaymentService(
    db: database.db,
    users: users,
    methods: PaymentMethodRepository(database.db),
    transactions: transactions,
  );
  final assistant = PaymentAssistantService(
    transactions: transactions,
    users: users,
    gateway: config.llmApiKey.isEmpty
        ? null
        : GroqChatGateway(apiKey: config.llmApiKey, model: config.llmModel),
  );
  final trips = TripService(
    vehicles: VehicleRepository(database.db),
    trips: TripRepository(database.db),
  );
  final reservations = ReservationService(
    db: database.db,
    reservations: ReservationRepository(database.db),
    trips: TripRepository(database.db),
    users: users,
  );
  final serviceNow = ServiceNowService(
    db: database.db,
    repository: ServiceNowRepository(database.db),
    payments: payments,
    geocoder: serviceNowGeocoder ?? NominatimAddressSearch(),
    routes: serviceNowRoutes ?? OsrmRoutePlanner(),
    photos: TeledocPhotoStore(p.join(uploadsDir, 'service_now')),
  );

  final foodSaveContext = foodSave ??
      FoodSaveContext(
        db: database.db,
        users: users,
        payments: payments,
        uploadsDir: uploadsDir,
        mailer: switch (sender) { ReservationMailer m => m, _ => null },
      );

  final coachService =
      coach ?? buildCoachService(database.db, users, payments);

  final router = Router()
    ..get('/health', (Request request) {
      return Response.ok(
        jsonEncode({
          'status': 'ok',
          'email_mode': config.emailConsoleMode ? 'console' : 'smtp',
          'time': DateTime.now().toIso8601String(),
        }),
        headers: {'content-type': 'application/json'},
      );
    })
    ..mount('/', buildAuthRoutes(auth).call)
    ..post('/auth/logout',
        (Request request) => handleLogout(request, auth))
    ..mount('/', buildUserRoutes(users, auth).call)
    ..mount('/', buildPaymentRoutes(payments, assistant: assistant).call)
    ..mount('/', buildFoodSaveRouter(foodSaveContext).call)
    ..mount('/', buildTripRoutes(trips).call)
    ..mount('/', buildReservationRoutes(reservations).call)
    ..mount('/', buildTeledocModule(database.db).call)
    ..mount('/', buildServiceNowRoutes(serviceNow).call)
    ..mount('/', buildCoachModule(coachService).call);

  final pipeline = Pipeline()
      .addMiddleware(requireAuth(sessions))
      .addHandler(router.call);

  return logRequestsMiddleware ? logRequests()(pipeline) : pipeline;
}
