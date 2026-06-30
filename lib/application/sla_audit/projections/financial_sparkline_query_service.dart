import 'financial_sparkline_series.dart';

abstract class FinancialSparklineQueryService {
  Future<FinancialSparklineSeries> getSparkline({
    required String organizationId,
    required int days,
  });
}
