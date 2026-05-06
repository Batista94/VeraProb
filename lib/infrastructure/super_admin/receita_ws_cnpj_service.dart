import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/super_admin/cnpj_company_data.dart';
import 'package:veraprob/domain/super_admin/cnpj_exceptions.dart';
import 'package:veraprob/domain/super_admin/i_cnpj_lookup_service.dart';
import 'package:veraprob/infrastructure/super_admin/cnpj_infrastructure_exceptions.dart';

/// ReceitaWS implementation of [ICnpjLookupService].
///
/// Routes through Supabase Edge Function `super-admin-proxy` to bypass CORS
/// and maintain architectural sovereignty (INV-14).
class ReceitaWsCnpjService implements ICnpjLookupService {
  final SupabaseClient _client;

  ReceitaWsCnpjService(this._client);

  @override
  Future<CnpjCompanyData?> lookup(String cnpjDigits) async {
    if (cnpjDigits.length != 14) {
      throw InvalidCnpjException(
        'CNPJ must be exactly 14 digits',
        reason: 'invalid_format',
        cnpj: cnpjDigits,
      );
    }

    late FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'super-admin-proxy',
        body: {
          'action': 'lookup_cnpj',
          'params': {'cnpj': cnpjDigits},
        },
      );
    } on TimeoutException {
      throw ServiceTimeoutException('CNPJ lookup timed out', cnpj: cnpjDigits);
    } on FunctionException catch (e) {
      if (e.status == 429) {
        throw RateLimitExceededException(
          'Registry rate limit reached',
          cnpj: cnpjDigits,
        );
      }
      throw ExternalApiException.fromStatusCode(
        e.status,
        cnpj: cnpjDigits,
      );
    } catch (_) {
      throw ExternalApiException(
        'Upstream request failed',
        sanitizedCode: 'upstream_server_error',
        cnpj: cnpjDigits,
      );
    }

    if (response.status == 429) {
      throw RateLimitExceededException(
        'Registry rate limit reached',
        cnpj: cnpjDigits,
      );
    }

    if (response.status != 200) {
      throw ExternalApiException.fromStatusCode(
        response.status,
        cnpj: cnpjDigits,
      );
    }

    final Map<String, dynamic> body;
    try {
      body = response.data as Map<String, dynamic>;
    } catch (_) {
      throw DataParsingException(
        'Unexpected response shape from proxy',
        cnpj: cnpjDigits,
      );
    }

    final data = body['data'];
    if (data == null) return null; // definitive not-found

    if (data is! Map<String, dynamic>) {
      throw DataParsingException(
        'Unexpected response shape from proxy',
        field: 'data',
        cnpj: cnpjDigits,
      );
    }

    if (data['status'] == 'ERROR') {
      throw InvalidCnpjException(
        'CNPJ inválido ou não encontrado',
        reason: 'api_status_error',
        cnpj: cnpjDigits,
      );
    }

    try {
      return CnpjCompanyData(
        cnpj: cnpjDigits,
        legalName: _trim(data['legalName'] as String?),
        tradeName: _trim(data['tradeName'] as String?),
        situation: _trim(data['situation'] as String?),
      );
    } on TypeError catch (e) {
      throw DataParsingException(
        'Contract drift in registry response',
        field: e.toString().contains('legalName')
            ? 'legalName'
            : e.toString().contains('tradeName')
            ? 'tradeName'
            : null,
        cnpj: cnpjDigits,
      );
    }
  }

  String? _trim(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return v.trim();
  }
}
