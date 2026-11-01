import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// Six independent code boxes with auto-advance and paste support.
class VerificationCodeInput extends StatefulWidget {
  const VerificationCodeInput({
    super.key,
    required this.onCompleted,
    this.enabled = true,
  });

  final ValueChanged<String> onCompleted;
  final bool enabled;

  @override
  State<VerificationCodeInput> createState() => VerificationCodeInputState();
}

class VerificationCodeInputState extends State<VerificationCodeInput> {
  static const _length = 6;

  final List<TextEditingController> _controllers =
      List.generate(_length, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(_length, (_) => FocusNode());

  String get code => _controllers.map((c) => c.text).join();
  bool get isComplete => code.length == _length;

  void clear() {
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes.first.requestFocus();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onChanged(int index, String value) {
    // Pasted full code: distribute across boxes.
    final cleaned = value.replaceAll(RegExp(r'\D'), '');
    if (cleaned.length > 1) {
      for (var i = 0; i < _length; i++) {
        _controllers[i].text = i < cleaned.length ? cleaned[i] : '';
      }
      if (isComplete) widget.onCompleted(code);
      setState(() {});
      return;
    }
    if (value.isNotEmpty && index < _length - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    setState(() {});
    if (isComplete) widget.onCompleted(code);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(_length, (index) {
        return SizedBox(
          width: 46,
          height: 56,
          child: TextField(
            controller: _controllers[index],
            focusNode: _focusNodes[index],
            enabled: widget.enabled,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: _length, // allows paste of a full 6-digit code
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
            decoration: const InputDecoration(
              counterText: '',
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (v) => _onChanged(index, v),
          ),
        );
      }),
    );
  }
}
