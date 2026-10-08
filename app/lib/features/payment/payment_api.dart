import 'package:proxilife_shared/proxilife_shared.dart';

import '../../core/api/api_client.dart';

/// Typed payment endpoints over [ApiClient].
class PaymentApi {
  PaymentApi(this._client);

  final ApiClient _client;

  Future<List<PaymentMethodDto>> listMethods() async {
    final data = await _client.getJson('/payment-methods');
    return (data['items'] as List)
        .map((e) => PaymentMethodDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PaymentMethodDto> addMethod({
    required PaymentMethodType type,
    String? numeroCarte,
    String? nomTitulaire,
    String? dateExpiration,
    bool parDefaut = false,
  }) async {
    final data = await _client.postJson('/payment-methods', {
      'type': type.apiValue,
      'numero_carte': ?numeroCarte,
      'nom_titulaire': ?nomTitulaire,
      'date_expiration': ?dateExpiration,
      'par_defaut': parDefaut,
    });
    return PaymentMethodDto.fromJson(data);
  }

  Future<void> deleteMethod(int id) =>
      _client.deleteJson('/payment-methods/$id');

  Future<void> setDefaultMethod(int id) =>
      _client.patchJson('/payment-methods/$id/default', {});

  Future<List<TransactionDto>> listTransactions({
    TransactionStatus? statut,
    ServiceType? service,
  }) async {
    final query = <String>[
      if (statut != null) 'statut=${statut.apiValue}',
      if (service != null) 'type_service=${service.apiValue}',
    ].join('&');
    final path = query.isEmpty ? '/transactions' : '/transactions?$query';
    final data = await _client.getJson(path);
    return (data['items'] as List)
        .map((e) => TransactionDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TransactionDto> createTransaction({
    required int montantCentimes,
    required String beneficiaireEmail,
    required ServiceType typeService,
    String? idReference,
    int? idMoyenPaiement,
  }) async {
    final data = await _client.postJson('/transactions', {
      'montant_centimes': montantCentimes,
      'beneficiaire_email': beneficiaireEmail,
      'type_service': typeService.apiValue,
      'id_reference':
          (idReference != null && idReference.isNotEmpty) ? idReference : null,
      'id_moyen_paiement': ?idMoyenPaiement,
    }..removeWhere((k, v) => v == null));
    return TransactionDto.fromJson(data);
  }

  Future<TransactionDto> refund(int id) async {
    final data = await _client
        .patchJson('/transactions/$id/status', {'statut': 'rembourse'});
    return TransactionDto.fromJson(data);
  }

  Future<void> cancel(int id) => _client.deleteJson('/transactions/$id');
}

/// Parses a French amount field ("12,50" / "12.50" / "12") to cents.
int? parseAmountToCents(String input) {
  final cleaned = input.trim().replaceAll(RegExp(r'\s'), '').replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d{0,2})?$').hasMatch(cleaned)) return null;
  final parts = cleaned.split('.');
  final euros = int.tryParse(parts[0]) ?? 0;
  final centsText = parts.length > 1 ? parts[1].padRight(2, '0') : '00';
  final cents = euros * 100 + (int.tryParse(centsText) ?? 0);
  return cents > 0 ? cents : null;
}
