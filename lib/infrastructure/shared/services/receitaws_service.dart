import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// @deprecated Use [cnpjLookupServiceProvider] from super_admin_providers.dart instead.
/// This service makes DIRECT HTTP calls to ReceitaWS from the browser, which is
/// blocked by CORS in web environments. The proxy-based [ReceitaWsCnpjService]
/// routes through the `super-admin-proxy` Edge Function (INV-14).
///
/// Retained only for unit test compatibility. Will be removed in a future cleanup.
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
    return ReceitaCompanyData(
      cnpj: json['cnpj'] ?? '',
      nome: json['nome'] ?? '',
      fantasia: json['fantasia'] ?? '',
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

  /// Busca os dados do CNPJ. Em caso de qualquer erro (Timeout, 500, Payload Invalido),
  /// retorna nulo para garantir a degradação graciosa da UI (Hostile Defense Attorney).
  Future<ReceitaCompanyData?> fetchCompanyByCnpj(String cnpj) async {
    try {
      final sanitizedCnpj = cnpj.replaceAll(RegExp(r'[^0-9]'), '');

      final response = await _client
          .get(Uri.parse('$_baseUrl/$sanitizedCnpj'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return null;
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;

      if (decoded['status'] == 'ERROR') {
        return null;
      }

      return ReceitaCompanyData.fromJson(decoded);
    } catch (e) {
      // Catch all exceptions including SocketException, FormatException (jsonDecode), etc.
      return null;
    }
  }
}

/// @deprecated Use [cnpjLookupServiceProvider] instead. See INV-14.
@Deprecated('Use cnpjLookupServiceProvider (proxy-based) instead.')
final receitaWsServiceProvider = Provider<ReceitaWsService>((ref) {
  return ReceitaWsService();
});
