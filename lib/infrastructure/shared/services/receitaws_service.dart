// ignore_for_file: deprecated_member_use_from_same_package
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:veraprob/features/super_admin/domain/cnpj_exceptions.dart';
import 'package:veraprob/features/super_admin/infrastructure/cnpj_infrastructure_exceptions.dart';

/// @deprecated Use [cnpjLookupServiceProvider] from super_admin_providers.dart instead.
/// Direct HTTP calls are blocked by CORS in browser context (INV-14).
@Deprecated('Use cnpjLookupServiceProvider (proxy-based) instead. See INV-14.')
class ReceitaCompanyData {
  final String cnpj;
  final String nome;
  final String fantasia;

  ReceitaCompanyData({
    required this.cnpj,
    required this.nome,
    required this.fantasia,
  });

  factory ReceitaCompanyData.fromJson(Map<String, dynamic> json) {
    final nome = json['nome'];
    final fantasia = json['fantasia'];
    if (nome is! String?) {
      throw const DataParsingException(
        'Contract drift in registry response',
        field: 'nome',
      );
    }
    if (fantasia is! String?) {
      throw const DataParsingException(
        'Contract drift in registry response',
        field: 'fantasia',
      );
    }
    return ReceitaCompanyData(
      cnpj: json['cnpj'] as String? ?? '',
      nome: nome ?? '',
      fantasia: fantasia ?? '',
    );
  }
}

/// @deprecated Use [cnpjLookupServiceProvider] from super_admin_providers.dart instead.
/// Direct HTTP calls are blocked by CORS in browser context (INV-14).
@Deprecated('Use cnpjLookupServiceProvider (proxy-based) instead. See INV-14.')
class ReceitaWsService {
  final http.Client _client;
  static const String _baseUrl = 'https://receitaws.com.br/v1/cnpj';

  ReceitaWsService({http.Client? client}) : _client = client ?? http.Client();

  /// Throws typed [CnpjLookupException] subtypes on all fault paths.
  ///
  /// Returns `null` only when the registry definitively has no record.
  Future<ReceitaCompanyData?> fetchCompanyByCnpj(String cnpj) async {
    final sanitizedCnpj = cnpj.trim().replaceAll(RegExp(r'[^0-9]'), '');

    if (sanitizedCnpj.length != 14) {
      throw InvalidCnpjException(
        'CNPJ inválido ou não encontrado',
        reason: 'invalid_format',
        cnpj: sanitizedCnpj,
      );
    }

    final http.Response response;
    try {
      response = await _client
          .get(Uri.parse('$_baseUrl/$sanitizedCnpj'))
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw ServiceTimeoutException(
        'CNPJ lookup timed out',
        cnpj: sanitizedCnpj,
      );
    } on SocketException {
      throw ExternalApiException(
        'Upstream request failed',
        sanitizedCode: 'upstream_server_error',
        cnpj: sanitizedCnpj,
      );
    }

    if (response.statusCode == 429) {
      throw RateLimitExceededException(
        'Registry rate limit reached',
        cnpj: sanitizedCnpj,
      );
    }

    if (response.statusCode != 200) {
      throw ExternalApiException.fromStatusCode(
        response.statusCode,
        cnpj: sanitizedCnpj,
      );
    }

    final Map<String, dynamic> decoded;
    try {
      final raw = jsonDecode(response.body);
      if (raw is! Map<String, dynamic>) {
        throw DataParsingException(
          'Unexpected response shape from registry',
          cnpj: sanitizedCnpj,
        );
      }
      decoded = raw;
    } on FormatException {
      throw DataParsingException(
        'Malformed JSON from registry',
        cnpj: sanitizedCnpj,
      );
    }

    if (decoded['status'] == 'ERROR') {
      throw InvalidCnpjException(
        'CNPJ inválido ou não encontrado',
        reason: 'api_status_error',
        cnpj: sanitizedCnpj,
      );
    }

    return ReceitaCompanyData.fromJson(decoded);
  }
}

/// @deprecated Use [cnpjLookupServiceProvider] instead. See INV-14.
@Deprecated('Use cnpjLookupServiceProvider (proxy-based) instead.')
final receitaWsServiceProvider = Provider<ReceitaWsService>((ref) {
  return ReceitaWsService();
});
