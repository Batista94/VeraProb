import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:veraprob/domain/super_admin/cnpj_company_data.dart';
import 'package:veraprob/domain/super_admin/i_cnpj_lookup_service.dart';

/// ReceitaWS implementation of [ICnpjLookupService].
///
/// Calls the free public API at receitaws.com.br.
/// Rate-limited to ~3 req/min on the free tier — acceptable for
/// interactive onboarding (one call per CNPJ typed by a SuperAdmin).
///
/// **INV-25:** ReceitaWS is free, no auth required, Brazilian government data.
/// **INV-4:** All domain types; no Supabase dependency.
class ReceitaWsCnpjService implements ICnpjLookupService {
  final http.Client _client;

  ReceitaWsCnpjService({http.Client? client})
    : _client = client ?? http.Client();

  @override
  Future<CnpjCompanyData?> lookup(String cnpjDigits) async {
    if (cnpjDigits.length != 14) return null;
    try {
      final uri = Uri.https('receitaws.com.br', '/v1/cnpj/$cnpjDigits');
      final response = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['status'] == 'ERROR') return null;

      return CnpjCompanyData(
        cnpj: cnpjDigits,
        legalName: _trim(json['nome'] as String?),
        tradeName: _trim(json['fantasia'] as String?),
        situation: _trim(json['situacao'] as String?),
      );
    } catch (_) {
      return null;
    }
  }

  String? _trim(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return v.trim();
  }
}
