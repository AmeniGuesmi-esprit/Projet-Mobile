import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Formats whole-cents amounts in `fr_FR` locale (e.g. "12,50 €").
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.cents, {
    super.key,
    this.style,
  });

  final int cents;
  final TextStyle? style;

  static final NumberFormat _format =
      NumberFormat.currency(locale: 'fr_FR', symbol: '€');

  static String format(int cents) => _format.format(cents / 100);

  @override
  Widget build(BuildContext context) {
    return Text(format(cents), style: style);
  }
}
