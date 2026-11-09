import 'dart:async';

import 'package:flutter/material.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/session/session_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../reservations/reservation_api.dart' show apiErrorMessage;
import '../trips/trip_labels.dart';
import 'service_now_api.dart';

/// Conversation between the client and the prestataire of a request.
class ServiceNowChatScreen extends StatefulWidget {
  const ServiceNowChatScreen({
    super.key,
    required this.session,
    required this.demandeId,
  });

  final SessionController session;
  final int demandeId;

  @override
  State<ServiceNowChatScreen> createState() => _ServiceNowChatScreenState();
}

class _ServiceNowChatScreenState extends State<ServiceNowChatScreen> {
  static const Duration _refreshInterval = Duration(seconds: 3);

  late final ServiceNowApi _api = ServiceNowApi(widget.session.api);
  final TextEditingController _input = TextEditingController();
  Timer? _timer;
  List<ServiceNowMessageDto> _messages = const [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(_refreshInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final messages = await _api.messages(widget.demandeId);
      if (mounted) setState(() => _messages = messages);
    } catch (_) {
      // Keeps the conversation on screen; the next refresh tries again.
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (ServiceNowRules.messageError(text) != null || _sending) return;
    setState(() => _sending = true);
    try {
      final messages = await _api.sendMessage(widget.demandeId, text);
      if (!mounted) return;
      _input.clear();
      setState(() => _messages = messages);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _bubble(ServiceNowMessageDto message) {
    final theme = Theme.of(context);
    final mine = message.auteurId == widget.session.user?.id;
    final textColor = mine ? AppColors.surface : AppColors.text;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.xs),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: mine ? AppColors.primary : AppColors.outlineSoft,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine)
                Text(
                  message.auteurNom,
                  style: theme.textTheme.bodySmall?.copyWith(color: textColor),
                ),
              Text(
                message.contenu,
                style: theme.textTheme.bodyLarge?.copyWith(color: textColor),
              ),
              Text(
                formatTripTime(message.creeLe.toLocal()),
                style: theme.textTheme.bodySmall?.copyWith(color: textColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = _messages.reversed.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Discussion')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : messages.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(AppSpacing.lg),
                            child: Text(
                              'Aucun message pour le moment.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.all(AppSpacing.md),
                          itemCount: messages.length,
                          itemBuilder: (_, i) => _bubble(messages[i]),
                        ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: ServiceNowRules.maxMessageLength,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Votre message',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  IconButton(
                    tooltip: 'Envoyer',
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send, color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
