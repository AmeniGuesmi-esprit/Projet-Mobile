import 'package:flutter_test/flutter_test.dart';
import 'package:proxilife/main.dart';

void main() {
  testWidgets('App builds the main shell with the three tabs', (tester) async {
    await tester.pumpWidget(const ProxiLifeApp());

    expect(find.text('ProxiLife'), findsOneWidget);
    expect(find.text('Accueil'), findsOneWidget);
    expect(find.text('Paiements'), findsOneWidget);
    expect(find.text('Profil'), findsOneWidget);
  });
}
