import 'package:equatable/equatable.dart';

/// Lean numeric sparkline series for CFO KPI cards (INV-4: cents as int).
class FinancialSparklineSeries extends Equatable {
  final List<int> protectedCents;
  final List<int> atRiskCents;
  final List<int> lostCents;
  final List<DateTime> datesUtc;

  const FinancialSparklineSeries({
    required this.protectedCents,
    required this.atRiskCents,
    required this.lostCents,
    required this.datesUtc,
  });

  bool get isEmpty => datesUtc.isEmpty;

  static const empty = FinancialSparklineSeries(
    protectedCents: [],
    atRiskCents: [],
    lostCents: [],
    datesUtc: [],
  );

  @override
  List<Object?> get props => [protectedCents, atRiskCents, lostCents, datesUtc];
}
