import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/super_admin/cnpj_company_data.dart';
import 'package:veraprob/domain/super_admin/i_cnpj_lookup_service.dart';

/// ReceitaWS implementation of [ICnpjLookupService].
///
/// Calls the free public API via Supabase Edge Function to bypass CORS and
/// maintain architectural sovereignty (INV-14).
class ReceitaWsCnpjService implements ICnpjLookupService {
  final SupabaseClient _client;

  ReceitaWsCnpjService(this._client);

  @override
  Future<CnpjCompanyData?> lookup(String cnpjDigits) async {
    if (cnpjDigits.length != 14) return null;

    try {
      final response = await _client.functions.invoke(
        'super-admin-proxy',
        body: {
          'action': 'lookup_cnpj',
          'params': {'cnpj': cnpjDigits},
        },
      );

      final data = (response.data as Map<String, dynamic>)['data'];
      if (data == null) return null;

      return CnpjCompanyData(
        cnpj: cnpjDigits,
        legalName: _trim(data['legalName'] as String?),
        tradeName: _trim(data['tradeName'] as String?),
        situation: _trim(data['situation'] as String?),
      );
    } catch (_) {
      return null; // Silent failure ensures UX gracefully falls back to manual entry
    }
  }

  String? _trim(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return v.trim();
  }
}
