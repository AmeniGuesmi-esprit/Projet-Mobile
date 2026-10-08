import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth/auth_middleware.dart';
import 'auth/session_service.dart';
import 'config/server_config.dart';
import 'db/database.dart';
import 'email/email_sender.dart';
import 'repositories/payment_method_repository.dart';
import 'repositories/transaction_repository.dart';
import 'repositories/user_repository.dart';
import 'repositories/verification_repository.dart';
import 'routes/auth_routes.dart';
import 'routes/payment_routes.dart';
import 'routes/user_routes.dart';
import 'services/auth_service.dart';
import 'services/payment_service.dart';

/// Wires repositories, services and routes into a single shelf [Handler].
/// Reusable by the real server (`bin/server.dart`) and by integration tests
/// (in-memory database + fake e-mail sender).
Handler buildApp(
  AppDatabase database,
  ServerConfig config, {
  EmailSender? emailSender,
  bool logRequestsMiddleware = true,
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
  final payments = PaymentService(
    db: database.db,
    users: users,
    methods: PaymentMethodRepository(database.db),
    transactions: TransactionRepository(database.db),
  );

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
    ..mount('/', buildPaymentRoutes(payments).call);

  final pipeline = Pipeline()
      .addMiddleware(requireAuth(sessions))
      .addHandler(router.call);

  return logRequestsMiddleware ? logRequests()(pipeline) : pipeline;
}
