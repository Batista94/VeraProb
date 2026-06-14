import 'package:equatable/equatable.dart';

/// Read-only projection of a single contract financial amendment
/// (renegotiation) sourced from `contract_financial_amendments` via an
/// org-scoped (RLS) table read. Append-only history — display only, no logic.
///
/// `penaltyMultiplierBps` is basis points of the penalty multiplier
/// (10000 bps = 1.00x). `financialCeilingCents` is `null` when the contract
/// carries no ceiling ("sem teto").
class ContractFinancialAmendmentView extends Equatable {
  final String id;
  final int? financialCeilingCents;
  final int penaltyMultiplierBps;
  final DateTime effectiveAtUtc;
  final DateTime amendedAtUtc;
  final String? notes;

  const ContractFinancialAmendmentView({
    required this.id,
    required this.financialCeilingCents,
    required this.penaltyMultiplierBps,
    required this.effectiveAtUtc,
    required this.amendedAtUtc,
    required this.notes,
  });

  factory ContractFinancialAmendmentView.fromJson(Map<String, dynamic> json) {
    return ContractFinancialAmendmentView(
      id: json['id'] as String,
      financialCeilingCents: (json['financial_ceiling_cents'] as num?)?.toInt(),
      penaltyMultiplierBps: (json['penalty_multiplier_bps'] as num).toInt(),
      effectiveAtUtc: DateTime.parse(
        json['effective_at_utc'] as String,
      ).toUtc(),
      amendedAtUtc: DateTime.parse(json['amended_at_utc'] as String).toUtc(),
      notes: json['notes'] as String?,
    );
  }

  /// Penalty multiplier formatted as a human factor (10000 bps → "1.00x").
  /// Pure integer math — never materialises a `double` in the financial domain
  /// (INV-4/INV-5).
  String get penaltyMultiplierLabel {
    final whole = penaltyMultiplierBps ~/ 10000;
    final hundredths = (penaltyMultiplierBps % 10000) ~/ 100;
    return '$whole.${hundredths.toString().padLeft(2, '0')}x';
  }

  @override
  List<Object?> get props => [
    id,
    financialCeilingCents,
    penaltyMultiplierBps,
    effectiveAtUtc,
    amendedAtUtc,
    notes,
  ];
}
