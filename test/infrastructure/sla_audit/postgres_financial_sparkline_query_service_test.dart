import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/sla_audit/projections/financial_sparkline_series.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_financial_sparkline_query_service.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class FakePostgrestFilterBuilder extends Fake
    implements PostgrestFilterBuilder<dynamic> {
  final dynamic _mockResult;
  FakePostgrestFilterBuilder(this._mockResult);

  @override
  Future<R> then<R>(
    FutureOr<R> Function(dynamic value) onValue, {
    Function? onError,
  }) async {
    return onValue(_mockResult);
  }
}

void main() {
  group('PostgresFinancialSparklineQueryService', () {
    late MockSupabaseClient mockClient;
    late PostgresFinancialSparklineQueryService service;

    setUp(() {
      mockClient = MockSupabaseClient();
      service = PostgresFinancialSparklineQueryService(mockClient);
    });

    test('should return empty series when RPC returns empty list', () async {
      when(
        () => mockClient.rpc<dynamic>(
          'get_financial_trend_sparkline',
          params: any(named: 'params'),
        ),
      ).thenAnswer((_) => FakePostgrestFilterBuilder(<dynamic>[]));

      final result = await service.getSparkline(
        organizationId: 'org-123',
        days: 7,
      );

      expect(result, equals(FinancialSparklineSeries.empty));
    });

    test('should map RPC results and ensure UTC dates (INV-6)', () async {
      final mockData = [
        {
          'protected_cents': 1000,
          'at_risk_cents': 200,
          'lost_cents': 50,
          'd': '2026-01-01T00:00:00Z',
        },
        {
          'protected_cents': 1100,
          'at_risk_cents': 100,
          'lost_cents': 20,
          'd': '2026-01-02T00:00:00Z',
        },
      ];

      when(
        () => mockClient.rpc<dynamic>(
          'get_financial_trend_sparkline',
          params: {'p_org_id': 'org-123', 'p_days': 7},
        ),
      ).thenAnswer((_) => FakePostgrestFilterBuilder(mockData));

      final result = await service.getSparkline(
        organizationId: 'org-123',
        days: 7,
      );

      expect(result.protectedCents, [1000, 1100]);
      expect(result.atRiskCents, [200, 100]);
      expect(result.lostCents, [50, 20]);
      expect(result.datesUtc.length, 2);

      // Ensure it parsed to UTC
      expect(result.datesUtc[0].isUtc, isTrue);
      expect(result.datesUtc[0], DateTime.utc(2026, 1, 1));
    });
  });
}
