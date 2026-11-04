import 'package:flutter/material.dart';

/// Full-width primary action with an in-button loading state, like the core
/// `PrimaryButton`, but whose label wraps instead of overflowing with large
/// font sizes (accessibility pass, D41). Material's `FilledButton.icon`
/// already lays its label out as `Flexible`.
class TeledocSubmitButton extends StatelessWidget {
  const TeledocSubmitButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: isLoading ? null : onPressed,
      icon: isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : Icon(icon, size: 20),
      label: Text(label, textAlign: TextAlign.center),
    );
  }
}
