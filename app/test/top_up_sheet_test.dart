import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proxilife/core/api/api_client.dart';
import 'package:proxilife/features/payment/top_up_sheet.dart';

void main() {
  Map<String, dynamic> cardJson(int id, {bool defaut = true}) => {
        'id': id,
        'type': 'carte_bancaire',
        'quatre_derniers_chiffres': '6467',
        'nom_titulaire': 'JOHN DOE',
        'date_expiration': '10/29',
        'par_defaut': defaut,
      };

  ApiClient apiFor(List<Map<String, dynamic>> methods,
      {void Function(Map<String, dynamic> body)? onTopUp,
      int topUpStatus = 200}) {
    // Response.bytes + explicit UTF-8: Response(String) encodes latin-1 and
    // breaks on accented French messages (« sélectionnée »).
    http.Response json(Object body, int status) => http.Response.bytes(
        utf8.encode(jsonEncode(body)), status,
        headers: {'content-type': 'application/json; charset=utf-8'});
    return ApiClient(
      httpClient: MockClient((request) async {
        if (request.url.path == '/payment-methods') {
          return json({'items': methods}, 200);
        }
        if (request.url.path == '/wallet/topup') {
          final body =
              jsonDecode(request.body) as Map<String, dynamic>;
          onTopUp?.call(body);
          if (topUpStatus >= 400) {
            return json({'error': 'La carte sélectionnée est expirée'},
                topUpStatus);
          }
          return json({'solde_centimes': 9250}, 200);
        }
        return json({}, 404);
      }),
    );
  }

  Future<int?> openSheet(WidgetTester tester, ApiClient api) async {
    int? credited;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async =>
                  credited = await TopUpSheet.show(context, api: api),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    return credited;
  }

  testWidgets('no card: guidance to add one first', (tester) async {
    await openSheet(tester, apiFor([]));

    expect(find.textContaining('Ajoutez d\'abord une carte bancaire'),
        findsOneWidget);
    expect(find.text('Ajouter une carte'), findsOneWidget);
    expect(find.text('Recharger'), findsNothing);
  });

  testWidgets('with a card: amount + preselected card tops up the wallet',
      (tester) async {
    Map<String, dynamic>? sent;
    int? credited;
    final api = apiFor([cardJson(7)], onTopUp: (b) => sent = b);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async =>
                  credited = await TopUpSheet.show(context, api: api),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();

    expect(find.text('Carte •••• 6467'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '20');
    await tester.tap(find.text('Recharger'));
    await tester.pumpAndSettle();

    expect(sent, {'montant_centimes': 2000, 'id_moyen_paiement': 7});
    expect(credited, 2000);
    // The sheet closed itself on success.
    expect(find.text('Recharger mon solde'), findsNothing);
  });

  testWidgets('server error keeps the sheet open with a French snackbar',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () =>
                  TopUpSheet.show(context, api: apiFor([cardJson(7)],
                      topUpStatus: 400)),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '20');
    await tester.tap(find.text('Recharger'));
    // pumpAndSettle hangs on the SnackBar's display timer: pump manually.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('La carte sélectionnée est expirée'), findsOneWidget);
    expect(find.text('Recharger mon solde'), findsOneWidget); // still open
  });
}
