import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxilife/core/live/live_refresh.dart';

/// Shows the latest value of [source]; refreshed by [LiveRefresh].
class _Counter extends StatefulWidget {
  const _Counter({required this.source});

  final Future<int> Function() source;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> with LiveRefresh<_Counter> {
  late Future<int> _future = widget.source();

  @override
  Future<void> liveRefresh() async {
    final value = await widget.source();
    if (!mounted) return;
    // Block body: setState must not return a Future.
    setState(() {
      _future = liveFuture(value);
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<int>(
        future: _future,
        builder: (context, snap) => snap.connectionState ==
                ConnectionState.waiting
            ? const Text('chargement')
            : Text('valeur ${snap.data}'),
      );
}

void main() {
  const tick = Duration(seconds: 10);
  late int value;
  late bool fail;

  Future<int> source() async {
    if (fail) throw Exception('serveur indisponible');
    return value;
  }

  setUp(() {
    value = 1;
    fail = false;
    LiveRefreshConfig.interval = tick;
  });

  testWidgets('updates in place every tick, keeps data on failure',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: _Counter(source: source)));
    await tester.pump();
    expect(find.text('valeur 1'), findsOneWidget);

    value = 2;
    await tester.pump(tick + const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('valeur 2'), findsOneWidget);
    expect(find.text('chargement'), findsNothing); // no loader flash

    fail = true;
    value = 3;
    await tester.pump(tick + const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('valeur 2'), findsOneWidget); // kept
  });

  testWidgets('paused while another page covers the screen', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: nav, home: _Counter(source: source)));
    await tester.pump();

    nav.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('autre page'))));
    await tester.pumpAndSettle();
    value = 5;
    await tester.pump(tick + const Duration(seconds: 1));
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('valeur 1'), findsOneWidget); // not refreshed meanwhile

    await tester.pump(tick + const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('valeur 5'), findsOneWidget);
  });
}
