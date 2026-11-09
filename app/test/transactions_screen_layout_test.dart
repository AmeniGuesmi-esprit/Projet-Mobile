import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:proxilife/core/api/api_client.dart';
import 'package:proxilife/core/theme/app_theme.dart';
import 'package:proxilife/features/payment/transactions_screen.dart';

void main() {
  setUpAll(() async {
    // Real font (Inter), so widths match the phone; the default test font
    // is much wider.
    final bytes = File('assets/fonts/Inter-VF.ttf').readAsBytesSync();
    final loader = FontLoader('Inter')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  });

  testWidgets('A CoachProche payment fits on a 360 dp phone', (tester) async {
    // Redmi-like screen: 360 dp wide.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final api = ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'items': [
              {
                'id': 1,
                'montant_centimes': 3000,
                'devise': 'TND',
                'date': '2026-11-09T14:00:00',
                'statut': 'echoue',
                'type_service': 'CoachProche',
                'facture_numero': 'F-1',
                'direction': 'debit',
                'beneficiaire_nom': 'Yasmine Chakroun',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );

    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: TransactionsScreen(api: api)),
      ),
    );
    await tester.pump();
    await tester.pump();
    FlutterError.onError = previous;

    expect(find.text('CoachProche'), findsWidgets);
    for (final e in errors) {
      debugPrint(e.toString());
    }
    // A RenderFlex overflow would be reported here.
    expect(errors, isEmpty);

    await tester.pumpWidget(const SizedBox());
  });
}
