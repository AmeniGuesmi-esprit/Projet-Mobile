import 'package:proxilife_server/src/api_error.dart';
import 'package:proxilife_server/src/db/database.dart';
import 'package:proxilife_server/src/repositories/transaction_repository.dart';
import 'package:proxilife_server/src/repositories/user_repository.dart';
import 'package:proxilife_server/src/services/payment_assistant_service.dart';
import 'package:test/test.dart';

/// Echo gateway: replies with the raw prompt so tests can inspect the exact
/// context sent to the LLM. No network.
class FakeGateway implements GroqGateway {
  int calls = 0;

  @override
  Future<String> complete(
      {required String systemPrompt, required String question}) async {
    calls++;
    return '$systemPrompt\n$question';
  }
}

void main() {
  late AppDatabase database;
  late UserRepository users;
  late TransactionRepository transactions;
  late FakeGateway gateway;
  late PaymentAssistantService assistant;

  const otherId = 2; // beneficiary/counterparty
  late int meId;

  Future<int> insertUser(String email, {int solde = 0, String? rib}) =>
      database.db.insert('utilisateur', {
        'nom': 'Doe',
        'prenom': 'John',
        'email': email,
        'telephone': '0612345678',
        'mot_de_passe_hash': 'x',
        'photo': null,
        'role': rib == null ? 'client' : 'conducteur',
        'statut_compte': 'actif',
        'rib': rib,
        'solde_centimes': solde,
        'cree_le': DateTime.now().toIso8601String(),
      });

  var factureCounter = 0;
  Future<void> insertTx({
    required int montant,
    required String statut,
    int? payerId,
    int? beneficiaryId,
    DateTime? date,
  }) =>
      database.db.insert('transaction_', {
        'montant_centimes': montant,
        'devise': 'TND',
        'date': (date ?? DateTime.now()).toIso8601String(),
        'statut': statut,
        'type_service': 'EcoRoute',
        'id_reference': null,
        'facture_numero': 'FAC-2026-${(++factureCounter).toString()}',
        'utilisateur_id': payerId,
        'beneficiaire_id': beneficiaryId,
        'moyen_paiement_id': null,
      });

  setUp(() async {
    database = await AppDatabase.inMemory();
    users = UserRepository(database.db);
    transactions = TransactionRepository(database.db);
    gateway = FakeGateway();
    assistant = PaymentAssistantService(
      transactions: transactions,
      users: users,
      gateway: gateway,
    );
    meId = await insertUser('me@test.fr', solde: 5000);
    await insertUser('other@test.fr', rib: '30004000011234567890173');
  });

  tearDown(() => database.close());

  test('off-topic question is declined without calling the model', () async {
    final reply = await assistant.ask(meId, 'Quelle heure est-il à Paris ?');
    expect(reply, PaymentAssistantService.offTopicReply);
    expect(gateway.calls, 0);
  });

  test('on-topic question gets grounded aggregates and recent history',
      () async {
    // Two payments sent today + one received; one failed (ignored).
    await insertTx(
        montant: 1500, statut: 'paye', payerId: meId, beneficiaryId: otherId);
    await insertTx(
        montant: 500, statut: 'paye', payerId: meId, beneficiaryId: otherId);
    await insertTx(
        montant: 800, statut: 'paye', payerId: otherId, beneficiaryId: meId);
    await insertTx(
        montant: 999, statut: 'echoue', payerId: meId, beneficiaryId: otherId);

    final reply =
        await assistant.ask(meId, 'Combien ai-je dépensé aujourd\'hui ?');

    expect(gateway.calls, 1);
    expect(reply, contains('"solde_actuel_dt":"50.00"'));
    expect(reply, contains('"depense_aujourdhui_dt":"20.00"'));
    expect(reply, contains('"recu_aujourdhui_dt":"8.00"'));
    expect(reply, contains('"contrepartie":"John Doe"'));
    // Failed payments never reach the model.
    expect(reply, isNot(contains('9.99')));
    // The restriction rules travel with every request.
    expect(reply, contains('UNIQUEMENT'));
  });

  test('échoue and en_attente transactions are not counted as spent',
      () async {
    await insertTx(
        montant: 700, statut: 'en_attente', payerId: meId, beneficiaryId: otherId);
    final reply = await assistant.ask(meId, 'Quel est mon solde ?');
    expect(reply, contains('"depense_aujourdhui_dt":"0.00"'));
    expect(reply, contains('"solde_actuel_dt":"50.00"'));
  });

  test('missing key → 503 with a French message', () async {
    final noKey = PaymentAssistantService(
      transactions: transactions,
      users: users,
      gateway: null,
    );
    expect(
      () => noKey.ask(meId, 'Quel est mon solde ?'),
      throwsA(isA<ApiError>()
          .having((e) => e.statusCode, 'statusCode', 503)),
    );
  });

  test('empty or overlong question → 400', () async {
    expect(() => assistant.ask(meId, '   '), throwsA(isA<ApiError>()));
    expect(() => assistant.ask(meId, 'solde' * 200), throwsA(isA<ApiError>()));
  });
}
