// pr_scanner: ignore-regression
// Council-reviewed (Sprint B SLA Versioning plan, approved 2026-06-12):
// rule lifecycle scheduling/retirement + financial amendments (INV-3/4/15/21).
import 'package:equatable/equatable.dart';

import 'package:veraprob/domain/shared/integrity_exception.dart';

class ContractFinancialAmendment extends Equatable {
  final String id;
  final String organizationId;
  final String contractId;
  final int? financialCeilingCents;
  final int penaltyMultiplierBps;
  final DateTime effectiveAtUtc;
  final DateTime amendedAtUtc;
  final String? amendedByUserId;
  final String? notes;

  const ContractFinancialAmendment({
    required this.id,
    required this.organizationId,
    required this.contractId,
    this.financialCeilingCents,
    required this.penaltyMultiplierBps,
    required this.effectiveAtUtc,
    required this.amendedAtUtc,
    this.amendedByUserId,
    this.notes,
  });

  factory ContractFinancialAmendment.create({
    required String id,
    required String organizationId,
    required String contractId,
    int? financialCeilingCents,
    required int penaltyMultiplierBps,
    required DateTime effectiveAtUtc,
    required DateTime amendedAtUtc,
    String? amendedByUserId,
    String? notes,
  }) {
    if (penaltyMultiplierBps <= 0) {
      throw const IntegrityException(
        'Penalty multiplier BPS must be > 0',
        field: 'penaltyMultiplierBps',
      );
    }
    return ContractFinancialAmendment(
      id: id,
      organizationId: organizationId,
      contractId: contractId,
      financialCeilingCents: financialCeilingCents,
      penaltyMultiplierBps: penaltyMultiplierBps,
      effectiveAtUtc: effectiveAtUtc,
      amendedAtUtc: amendedAtUtc,
      amendedByUserId: amendedByUserId,
      notes: notes,
    );
  }

  @override
  List<Object?> get props => [
    id,
    organizationId,
    contractId,
    financialCeilingCents,
    penaltyMultiplierBps,
    effectiveAtUtc,
    amendedAtUtc,
    amendedByUserId,
    notes,
  ];
}
