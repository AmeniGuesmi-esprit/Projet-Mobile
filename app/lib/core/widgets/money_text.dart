import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Formats whole-cents amounts in Tunisian Dinar (e.g. "12,50 DT").
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.cents, {
    super.key,
    this.style,
  });

  final int cents;
  final TextStyle? style;

  static final NumberFormat _format =
      NumberFormat.currency(locale: 'fr_TN', symbol: 'DT');

  static String format(int cents) => _format.format(cents / 100);

  @override
  Widget build(BuildContext context) {
    return Text(format(cents), style: style);
  }
}
