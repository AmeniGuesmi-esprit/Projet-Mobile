import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../domain/teledoc_formatters.dart';
import '../../../domain/teledoc_repository.dart';
import '../../widgets/teledoc_async_view.dart';
import '../../widgets/teledoc_chips.dart';

/// Patient: a past consultation and its prescription.
class TeledocConsultationDetailScreen extends StatefulWidget {
  const TeledocConsultationDetailScreen({
    super.key,
    required this.repository,
    required this.consultationId,
  });

  final TeledocRepository repository;
  final int consultationId;

  @override
  State<TeledocConsultationDetailScreen> createState() =>
      _TeledocConsultationDetailScreenState();
}

class _TeledocConsultationDetailScreenState
    extends State<TeledocConsultationDetailScreen> {
  late Future<TeledocConsultationDto> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.consultation(widget.consultationId);
  }

  void _reload() => setState(() {
    _future = widget.repository.consultation(widget.consultationId);
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Consultation')),
      body: TeledocAsyncView<TeledocConsultationDto>(
        future: _future,
        onRetry: _reload,
        builder: (context, c) => ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Text(c.motif, style: theme.textTheme.headlineMedium),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                TeledocStatusChip(c.statutDemande),
                TeledocUrgencyChip(c.urgence),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TeledocSection(
              title: 'Déroulement',
              child: Column(
                children: [
                  TeledocInfoRow('Médecin', 'Dr ${c.medecinNom ?? '—'}'),
                  TeledocInfoRow('Type', c.type.label),
                  TeledocInfoRow('Début', teledocDate(c.dateDebut)),
                  TeledocInfoRow(
                    'Durée',
                    teledocDuration(c.dateDebut, c.dateFin),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TeledocSection(
              title: 'Ordonnance',
              trailing: c.ordonnance == null
                  ? null
                  : IconButton(
                      tooltip: 'Copier l\'ordonnance',
                      icon: const Icon(Icons.copy, size: 20),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: c.ordonnance!),
                        );
                        if (context.mounted) {
                          showTeledocSnack(context, 'Ordonnance copiée');
                        }
                      },
                    ),
              child: Text(
                c.ordonnance ??
                    (c.statutDemande == TeledocRequestStatus.annulee
                        ? 'Consultation interrompue : aucune ordonnance.'
                        : 'L\'ordonnance sera disponible à la fin de la '
                              'consultation.'),
                style: theme.textTheme.bodyLarge,
              ),
            ),
            if (c.pharmacieNom != null) ...[
              const SizedBox(height: AppSpacing.md),
              TeledocSection(
                title: 'Pharmacie',
                child: Row(
                  children: [
                    const Icon(
                      Icons.local_pharmacy_outlined,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        c.pharmacieNom!,
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
