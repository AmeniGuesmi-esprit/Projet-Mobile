import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import 'payment_api.dart';

class _ChatMessage {
  const _ChatMessage(this.text, {required this.fromUser});

  final String text;
  final bool fromUser;
}

/// « Assistant paiements » chat: answers only payment questions (scope is
/// enforced server-side). Shown as a modal sheet from the Paiements tab.
class PaymentAssistantSheet extends StatefulWidget {
  const PaymentAssistantSheet({super.key, required this.api});

  final ApiClient api;

  static Future<void> show(BuildContext context, ApiClient api) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => PaymentAssistantSheet(api: api),
    );
  }

  static const List<String> suggestions = [
    'Combien ai-je dépensé aujourd\'hui ?',
    'Qui m\'a payé hier ?',
    'Quel est mon solde actuel ?',
  ];

  @override
  State<PaymentAssistantSheet> createState() => _PaymentAssistantSheetState();
}

class _PaymentAssistantSheetState extends State<PaymentAssistantSheet> {
  late final PaymentApi _payments = PaymentApi(widget.api);
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_ChatMessage> _history = [];
  String? _lastQuestion;
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send(String text) async {
    final question = text.trim();
    if (question.isEmpty || _sending) return;
    _lastQuestion = question;
    _input.clear();
    setState(() {
      _history.add(_ChatMessage(question, fromUser: true));
      _sending = true;
    });
    _scrollToBottom();
    try {
      final reply = await _payments.askAssistant(question);
      if (!mounted) return;
      setState(() {
        _history.add(_ChatMessage(reply, fromUser: false));
        _sending = false;
      });
      _scrollToBottom();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message),
        action: SnackBarAction(
          label: 'Réessayer',
          onPressed: () => _send(_lastQuestion ?? ''),
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_awesome_outlined,
                        color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Assistant paiements',
                            style: theme.textTheme.titleLarge),
                        Text('Uniquement vos paiements et votre solde',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fermer',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: _history.isEmpty
                    ? Center(
                        child: Text(
                          'Posez votre question sur vos paiements,\n'
                          'par exemple « Combien ai-je dépensé cette '
                          'semaine ? »',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        itemCount: _history.length + (_sending ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i == _history.length) {
                            return const _TypingBubble();
                          }
                          return _Bubble(_history[i]);
                        },
                      ),
              ),
              if (_history.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final s in PaymentAssistantSheet.suggestions)
                        ActionChip(
                          label: Text(s),
                          onPressed: _sending ? null : () => _send(s),
                        ),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        hintText: 'Votre question…',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton.filled(
                    tooltip: 'Envoyer',
                    onPressed: _sending ? null : () => _send(_input.text),
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.message);

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fromUser = message.fromUser;
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: fromUser
              ? AppColors.primary
              : AppColors.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Text(
          message.text,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: fromUser ? Colors.white : AppColors.text,
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
