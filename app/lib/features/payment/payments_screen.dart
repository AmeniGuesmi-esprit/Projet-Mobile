import 'package:flutter/material.dart';

import '../../core/session/session_controller.dart';
import '../../core/theme/app_colors.dart';
import 'new_payment_screen.dart';
import 'transactions_screen.dart';

/// Paiements hub: transactions list, with the accent FAB that starts the
/// unified payment flow.
class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key, required this.session});

  final SessionController session;

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  final GlobalKey<TransactionsScreenState> _txKey =
      GlobalKey<TransactionsScreenState>();

  Future<void> _newPayment() async {
    final created = await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => NewPaymentScreen(session: widget.session),
      ),
    );
    if (created == true) {
      _txKey.currentState?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TransactionsScreen(key: _txKey, api: widget.session.api),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'paiementFab',
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.text,
        icon: const Icon(Icons.add),
        label: const Text('Payer'),
        onPressed: _newPayment,
      ),
    );
  }
}
