import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proxilife/core/api/api_client.dart';
import 'package:proxilife/features/payment/payment_assistant_sheet.dart';

void main() {
  Future<void> pumpSheet(WidgetTester tester, ApiClient api) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: PaymentAssistantSheet(api: api))),
    );
    await tester.pump();
  }

  testWidgets('suggestions visible; asking shows the answer bubble',
      (tester) async {
    final api = ApiClient(
      httpClient: MockClient((request) async {
        expect(request.url.path, '/assistant/ask');
        expect(request.method, 'POST');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['question'], contains('solde'));
        return http.Response(
            jsonEncode({'reponse': 'Votre solde est de 50,00 DT.'}), 200);
      }),
    );
    await pumpSheet(tester, api);

    // Suggestion chips for empty conversation.
    expect(find.text('Quel est mon solde actuel ?'), findsOneWidget);
    expect(find.text('Combien ai-je dépensé aujourd\'hui ?'), findsOneWidget);

    await tester.tap(find.text('Quel est mon solde actuel ?'));
    await tester.pump(); // user bubble + typing indicator
    await tester.pumpAndSettle(); // reply in

    expect(find.text('Votre solde est de 50,00 DT.'), findsOneWidget);
    // Once the conversation started, suggestions disappear.
    expect(find.text('Combien ai-je dépensé aujourd\'hui ?'), findsNothing);
  });

  testWidgets('server error shows a French snackbar with Réessayer',
      (tester) async {
    final api = ApiClient(
      httpClient: MockClient((request) async => http.Response(
          jsonEncode({'error': 'Assistant indisponible pour le moment'}),
          503)),
    );
    await pumpSheet(tester, api);

    await tester.enterText(
        find.byType(TextField), 'Combien ai-je dépensé aujourd\'hui ?');
    await tester.tap(find.byTooltip('Envoyer'));
    await tester.pumpAndSettle();

    expect(find.text('Assistant indisponible pour le moment'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });
}
