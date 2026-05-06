import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:veraprob/infrastructure/shared/services/receitaws_service.dart';

void main() {
  group('ReceitaWsService (CT17)', () {
    late ReceitaWsService service;
    late MockClient mockClient;

    test('Happy Path: Converts correct JSON to POCO', () async {
      final mockJson = {
        "status": "OK",
        "cnpj": "12.345.678/0001-90",
        "nome": "EMPRESA DE TESTE S.A.",
        "fantasia": "TESTE",
        "abertura": "01/01/2000"
      };

      mockClient = MockClient((request) async {
        return http.Response(jsonEncode(mockJson), 200);
      });

      service = ReceitaWsService(client: mockClient);

      final result = await service.fetchCompanyByCnpj('12345678000190');

      expect(result, isNotNull);
      expect(result?.cnpj, '12.345.678/0001-90');
      expect(result?.nome, 'EMPRESA DE TESTE S.A.');
    });

    test('Adverse Path: Handles HTTP 500 securely (Error Boundary)', () async {
      mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      service = ReceitaWsService(client: mockClient);

      final result = await service.fetchCompanyByCnpj('12345678000190');

      // Graceful degradation: returns null on failure instead of throwing unhandled exceptions
      expect(result, isNull);
    });

    test('Adverse Path: Handles SocketException (Timeout) securely', () async {
      mockClient = MockClient((request) async {
        throw const SocketException('Connection timed out');
      });

      service = ReceitaWsService(client: mockClient);

      final result = await service.fetchCompanyByCnpj('12345678000190');

      expect(result, isNull);
    });

    test('Adverse Path: Handles Malformed JSON securely', () async {
      mockClient = MockClient((request) async {
        return http.Response('{"status": "OK", "nome": }', 200); // Invalid JSON
      });

      service = ReceitaWsService(client: mockClient);

      final result = await service.fetchCompanyByCnpj('12345678000190');

      expect(result, isNull);
    });
    
    test('Adverse Path: Handles API Error Status (e.g. Rate Limit / Invalid CNPJ)', () async {
      final mockJson = {
        "status": "ERROR",
        "message": "CNPJ Invalido"
      };

      mockClient = MockClient((request) async {
        return http.Response(jsonEncode(mockJson), 200);
      });

      service = ReceitaWsService(client: mockClient);

      final result = await service.fetchCompanyByCnpj('12345678000190');

      expect(result, isNull);
    });
  });
}
