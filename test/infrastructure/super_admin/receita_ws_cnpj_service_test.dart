import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/features/super_admin/infrastructure/receita_ws_cnpj_service.dart';

import 'receita_ws_cnpj_service_test.mocks.dart';

@GenerateMocks([SupabaseClient, FunctionsClient])
void main() {
  late MockSupabaseClient mockSupabaseClient;
  late MockFunctionsClient mockFunctionsClient;
  late ReceitaWsCnpjService service;

  setUp(() {
    mockSupabaseClient = MockSupabaseClient();
    mockFunctionsClient = MockFunctionsClient();

    when(mockSupabaseClient.functions).thenReturn(mockFunctionsClient);

    service = ReceitaWsCnpjService(mockSupabaseClient);
  });

  group('ReceitaWsCnpjService via Edge Function', () {
    test('lookup calls super-admin-proxy action lookup_cnpj', () async {
      const cnpj = '45518855000147';

      when(
        mockFunctionsClient.invoke(
          'super-admin-proxy',
          body: {
            'action': 'lookup_cnpj',
            'params': {'cnpj': cnpj},
          },
        ),
      ).thenAnswer(
        (_) async => FunctionResponse(
          status: 200,
          data: {
            'data': {
              'cnpj': cnpj,
              'legalName': 'Viação Cometa Azul',
              'tradeName': 'Cometa Azul',
              'situation': 'ATIVA',
            },
          },
        ),
      );

      final result = await service.lookup(cnpj);

      expect(result, isNotNull);
      expect(result!.cnpj, equals(cnpj));
      expect(result.legalName, equals('Viação Cometa Azul'));
      expect(result.tradeName, equals('Cometa Azul'));
      expect(result.situation, equals('ATIVA'));

      verify(
        mockFunctionsClient.invoke(
          'super-admin-proxy',
          body: {
            'action': 'lookup_cnpj',
            'params': {'cnpj': cnpj},
          },
        ),
      ).called(1);
    });

    test('lookup returns null when edge function throws', () async {
      when(
        mockFunctionsClient.invoke(any, body: anyNamed('body')),
      ).thenThrow(Exception('Edge Function Failed'));

      final result = await service.lookup('45518855000147');

      expect(result, isNull);
    });
  });
}
