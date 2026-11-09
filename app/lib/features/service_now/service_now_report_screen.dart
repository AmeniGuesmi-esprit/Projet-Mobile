import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/session/session_controller.dart';
import '../../core/widgets/money_text.dart';
import 'service_now_api.dart';
import 'service_now_format.dart';

/// PDF report of a finished intervention: preview, share and print.
class ServiceNowReportScreen extends StatelessWidget {
  const ServiceNowReportScreen({
    super.key,
    required this.session,
    required this.demande,
  });

  final SessionController session;
  final DemandeServiceDto demande;

  /// Null when the photo is absent or cannot be downloaded.
  Future<pw.MemoryImage?> _photo(
    InterventionDto intervention,
    InterventionPhotoKind kind,
  ) async {
    final exists = kind == InterventionPhotoKind.avant
        ? intervention.aPhotoAvant
        : intervention.aPhotoApres;
    if (!exists) return null;
    try {
      final source = ServiceNowApi(session.api).photoSource(
        intervention.id,
        kind,
      );
      final response =
          await http.get(Uri.parse(source.url), headers: source.headers);
      return response.statusCode == 200
          ? pw.MemoryImage(response.bodyBytes)
          : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final intervention = demande.intervention!;
    return Scaffold(
      appBar: AppBar(title: Text('Rapport n° ${intervention.id}')),
      body: PdfPreview(
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        pdfFileName: 'rapport-intervention-${intervention.id}.pdf',
        build: (format) async => buildInterventionReport(
          demande,
          intervention,
          format: format,
          photoAvant: await _photo(intervention, InterventionPhotoKind.avant),
          photoApres: await _photo(intervention, InterventionPhotoKind.apres),
        ),
      ),
    );
  }
}

/// The built-in PDF fonts only cover Latin-1: anything else is replaced so
/// that a message containing an emoji cannot break the document.
String _printable(String value) {
  final text = value
      .replaceAll('’', "'")
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll('œ', 'oe')
      .replaceAll(' ', ' ');
  return String.fromCharCodes(
    text.runes.map((rune) => rune > 255 ? 0x3F : rune),
  );
}

/// Builds the report's bytes.
Future<Uint8List> buildInterventionReport(
  DemandeServiceDto demande,
  InterventionDto intervention, {
  required PdfPageFormat format,
  pw.MemoryImage? photoAvant,
  pw.MemoryImage? photoApres,
}) async {
  pw.Widget line(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 130,
              child: pw.Text(
                _printable(label),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Expanded(child: pw.Text(_printable(value))),
          ],
        ),
      );

  pw.Widget title(String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
        child: pw.Text(
          _printable(value),
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blueGrey800,
          ),
        ),
      );

  pw.Widget photo(String label, pw.MemoryImage? image) => pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(_printable(label)),
            pw.SizedBox(height: 4),
            if (image != null)
              pw.Image(image, height: 170, fit: pw.BoxFit.contain)
            else
              pw.Text('Aucune photo'),
          ],
        ),
      );

  final paymentLabel = switch (intervention.paiementStatut) {
    TransactionStatus.paye => 'Payée',
    TransactionStatus.enAttente => 'En espèces, à confirmer',
    TransactionStatus.rembourse => 'Remboursée',
    TransactionStatus.echoue || null => 'Non payée',
  };

  final document = pw.Document(
    title: 'Rapport d\'intervention ${intervention.id}',
    author: 'ProxiLife',
  );
  document.addPage(
    pw.MultiPage(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(36),
      build: (_) => [
        pw.Text(
          'ProxiLife - ServiceNow',
          style: const pw.TextStyle(color: PdfColors.blueGrey600),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          _printable('Rapport d\'intervention n° ${intervention.id}'),
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.Divider(),
        title('Demande'),
        line('Service', demande.type.label),
        line('Description', demande.description),
        line('Adresse', demande.adresse),
        line('Client', demande.clientNom),
        title('Intervention'),
        line('Prestataire', intervention.prestataireNom ?? 'Compte supprimé'),
        line('Date prévue', formatServiceDate(intervention.datePrevue)),
        if (intervention.dateDebut != null)
          line('Début', formatServiceDate(intervention.dateDebut!)),
        if (intervention.dateFin != null)
          line('Fin', formatServiceDate(intervention.dateFin!)),
        line('Présence', 'Vérifiée par le code du client'),
        title('Rapport'),
        pw.Text(_printable(intervention.rapport ?? '')),
        title('Photos'),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            photo('Avant', photoAvant),
            pw.SizedBox(width: 12),
            photo('Après', photoApres),
          ],
        ),
        title('Règlement'),
        line('Montant', MoneyText.format(intervention.prixCentimes)),
        line('Paiement', paymentLabel),
        if (intervention.note != null)
          line('Note du client', '${intervention.note}/5'),
        if (intervention.commentaire != null)
          line('Commentaire', intervention.commentaire!),
      ],
    ),
  );
  return document.save();
}
