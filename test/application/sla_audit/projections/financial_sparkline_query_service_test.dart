import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/sla_audit/projections/financial_sparkline_query_service.dart';
import 'package:veraprob/application/sla_audit/projections/financial_sparkline_series.dart';

class MockFinancialSparklineQueryService extends Mock
    implements FinancialSparklineQueryService {}

void main() {
  group('FinancialSparklineQueryService Contract', () {
    late FinancialSparklineQueryService service;

    setUp(() {
      service = MockFinancialSparklineQueryService();
    });

    test('should allow mocking getSparkline', () async {
      final mockSeries = FinancialSparklineSeries(
        protectedCents: [1000],
        atRiskCents: [200],
        lostCents: [50],
        datesUtc: [DateTime.utc(2026, 1, 1)],
      );

      when(
        () => service.getSparkline(
          organizationId: any(named: 'organizationId'),
          days: any(named: 'days'),
        ),
      ).thenAnswer((_) async => mockSeries);

      final result = await service.getSparkline(
        organizationId: 'org-123',
        days: 7,
      );

      expect(result, equals(mockSeries));
      expect(result.protectedCents.first, 1000);
      expect(result.datesUtc.first.isUtc, isTrue);

      verify(
        () => service.getSparkline(organizationId: 'org-123', days: 7),
      ).called(1);
    });
  });
}
