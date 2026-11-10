import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:proxilife_shared/proxilife_shared.dart';

import '../api_error.dart';
import '../repositories/transaction_repository.dart';
import '../repositories/user_repository.dart';

/// One LLM call. Abstract so tests inject a fake (no network), like
/// [AddressGeocoder].
abstract class GroqGateway {
  Future<String> complete(
      {required String systemPrompt, required String question});

  static const String unavailableMessage =
      'Assistant indisponible pour le moment';
}

/// Groq chat completions (OpenAI-compatible API). The API key never leaves
/// the server: the app only talks to `/assistant/ask`.
class GroqChatGateway implements GroqGateway {
  GroqChatGateway({
    required this.apiKey,
    required this.model,
    HttpClient? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? HttpClient();

  final String apiKey;
  final String model;
  final HttpClient _client;
  final Duration timeout;

  @override
  Future<String> complete({
    required String systemPrompt,
    required String question,
  }) async {
    final uri = Uri.https('api.groq.com', '/openai/v1/chat/completions');
    final payload = jsonEncode({
      'model': model,
      'temperature': 0.2,
      // Headroom: reasoning models spend completion tokens on their
      // internal reasoning before the visible answer.
      'max_tokens': 800,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': question},
      ],
    });

    final HttpClientResponse response;
    try {
      final request = await _client
          .postUrl(uri)
          .timeout(timeout);
      request.headers
        ..set('content-type', 'application/json')
        ..set('authorization', 'Bearer $apiKey');
      request.add(utf8.encode(payload));
      response = await request.close().timeout(timeout);
      final raw = await utf8.decodeStream(response).timeout(timeout);
      if (response.statusCode >= 400) {
        throw const FormatException(); // mapped to a French message below
      }
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final choices = data['choices'] as List;
      final content = (choices.first as Map<String, dynamic>)['message']
          as Map<String, dynamic>;
      return (content['content'] as String).trim();
    } on SocketException {
      throw ApiError(503, GroqGateway.unavailableMessage);
    } on TimeoutException {
      throw ApiError(503, GroqGateway.unavailableMessage);
    } on HttpException {
      throw ApiError(503, GroqGateway.unavailableMessage);
    } on FormatException {
      throw ApiError(503, GroqGateway.unavailableMessage);
    }
  }
}

/// « Assistant paiements » : answers questions about the user's own wallet
/// only — transactions, balance, invoices. Anything else is declined.
///
/// The model never sees the database: the service builds a compact JSON
/// context (balance, computed aggregates, last transactions) and a French
/// system prompt that forbids out-of-scope answers. A keyword pre-filter
/// refuses obviously off-topic questions without any API call.
class PaymentAssistantService {
  PaymentAssistantService({
    required this.transactions,
    required this.users,
    required GroqGateway? gateway,
  }) : _gateway = gateway;

  final TransactionRepository transactions;
  final UserRepository users;
  final GroqGateway? _gateway;

  /// Answer canned for off-topic questions (also the model's fallback rule).
  static const String offTopicReply =
      'Je ne réponds qu\'aux questions sur vos paiements ProxiLife : '
      'solde, transactions, dépenses, remboursements et factures.';

  /// Payment-domain keywords (French, lowercase matching). Anything without
  /// one of these is declined without calling the model.
  static const List<String> _paymentKeywords = [
    'solde', 'dépen', 'depen', 'pay', 'reçu', 'recu', 'reçois', 'recois',
    'recevoir', 'reçeu', 'rembours', 'transaction', 'portefeuille', 'facture',
    'montant', 'argent', 'dinar', 'dt', 'débit', 'debit', 'crédit', 'credit',
    'envoyé', 'envoye', 'transfér', 'transfer', 'carte bancaire', 'espèce',
    'espece', 'gagné', 'gagne', 'encaiss', 'payeur', 'bénéficiaire',
    'beneficiaire', 'combien',
  ];

  bool _isOnTopic(String question) {
    final lower = question.toLowerCase();
    return _paymentKeywords.any(lower.contains);
  }

  Future<String> ask(int userId, String question) async {
    question = question.trim();
    if (question.isEmpty || question.length > 500) {
      throw ApiError.badRequest('Question requise (500 caractères max)');
    }
    final gateway = _gateway;
    if (gateway == null) {
      throw ApiError(503, GroqGateway.unavailableMessage);
    }
    // Obviously off-topic: decline without calling the model.
    if (!_isOnTopic(question)) return offTopicReply;

    final rows = await transactions.listForUser(userId);
    final solde = await users.findById(userId);
    final context = _buildContext(userId, rows,
        (solde?['solde_centimes'] as int?) ?? 0);
    return gateway.complete(
      systemPrompt: _systemPrompt,
      question: '$context\n\nQuestion de l\'utilisateur : $question',
    );
  }

  /// Compact, payment-only context: balance, Dart-computed aggregates
  /// (reliable numbers; the model never has to sum) and the last
  /// transactions. Amounts in DT so the model quotes them as-is.
  static String _buildContext(
      int userId, List<Map<String, Object?>> rows, int soldeCentimes) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int spentIn(DateTime from) => rows
        .where((r) =>
            r['utilisateur_id'] == userId &&
            r['statut'] == TransactionStatus.paye.apiValue &&
            !DateTime.parse(r['date'] as String).isBefore(from))
        .fold(0, (s, r) => s + (r['montant_centimes'] as int));
    int receivedIn(DateTime from) => rows
        .where((r) =>
            r['beneficiaire_id'] == userId &&
            r['statut'] == TransactionStatus.paye.apiValue &&
            !DateTime.parse(r['date'] as String).isBefore(from))
        .fold(0, (s, r) => s + (r['montant_centimes'] as int));

    String dt(int cents) => (cents / 100).toStringAsFixed(2);
    String name(Map<String, Object?> r, String prefix) {
      final n = r['${prefix}_nom'];
      final p = r['${prefix}_prenom'];
      final e = r['${prefix}_email'];
      return n == null ? (e as String? ?? 'inconnu') : '$p $n';
    }

    // Failed payments are noise for the model (and never moved money).
    final recent = rows
        .where((r) => r['statut'] != TransactionStatus.echoue.apiValue)
        .take(30)
        .map((r) {
      final isDebit = r['utilisateur_id'] == userId;
      return {
        'date': r['date'],
        'sens': isDebit ? 'envoyé' : 'reçu',
        'montant_dt': dt(r['montant_centimes'] as int),
        'statut': r['statut'],
        'service': r['type_service'],
        'contrepartie': isDebit ? name(r, 'b') : name(r, 'p'),
        'facture': r['facture_numero'],
      };
    }).toList();

    return jsonEncode({
      'date_du_jour': today.toIso8601String(),
      'solde_actuel_dt': dt(soldeCentimes),
      'depense_aujourdhui_dt': dt(spentIn(today)),
      'recu_aujourdhui_dt': dt(receivedIn(today)),
      // « Hier » = depuis hier matin moins depuis aujourd'hui.
      'depense_hier_dt': dt(
          spentIn(today.subtract(const Duration(days: 1))) - spentIn(today)),
      'recu_hier_dt': dt(receivedIn(today.subtract(const Duration(days: 1))) -
          receivedIn(today)),
      'depense_7_derniers_jours_dt':
          dt(spentIn(today.subtract(const Duration(days: 7)))),
      'recu_7_derniers_jours_dt':
          dt(receivedIn(today.subtract(const Duration(days: 7)))),
      'depense_mois_courant_dt':
          dt(spentIn(DateTime(now.year, now.month))),
      'transactions_recentes': recent,
    });
  }

  static const String _systemPrompt = '''
Tu es l'assistant Paiements de l'application ProxiLife. Règles strictes :
1. Tu réponds UNIQUEMENT aux questions sur les paiements de l'utilisateur : solde, transactions, dépenses, sommes reçues, remboursements, factures, moyens de paiement.
2. Tu te bases EXCLUSIVEMENT sur les données JSON fournies dans le message de l'utilisateur. Si l'information n'y figure pas, dis que tu n'as pas cette information — n'invente jamais de montant ni de nom.
3. Pour toute question hors sujet (météo, actualité, aide générale, code, etc.), réponds uniquement : "$offTopicReply"
4. Réponds en français, en une ou deux phrases, montants en DT (les champs *_dt sont déjà en dinars).
5. Les agrégats (depense_/recu_...) sont exacts : utilise-les tels quels au lieu de recalculer.
''';
}
