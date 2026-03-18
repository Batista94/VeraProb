import 'package:equatable/equatable.dart';

import 'domain_exception.dart';

/// Immutable value object carrying the legal metadata for an [AuditPackage] export.
///
/// Every exported document (PDF and CSV) must include this header — INV-19.
/// Absence of attestation is treated as a system error, not a missing feature.
///
/// Covers Brazilian legal requirements:
/// - CPC Art. 369–376 (Provas Documentais): digital authenticity statement.
/// - LGPD Art. 37 (Registro de Operações): identifies responsible party.
class AttestationHeader extends Equatable {
  // ── Issuing party (tenant / operator) ─────────────────────────────────────
  final String tenantName;

  /// Brazilian CNPJ of the operator. Format: "XX.XXX.XXX/XXXX-XX" or raw digits.
  /// Null only in test/sandbox environments where no real legal entity exists.
  final String? tenantCnpj;

  // ── Counterparty (contractor) ──────────────────────────────────────────────
  final String contractorName;

  /// Brazilian CNPJ of the contractor.
  final String? contractorCnpj;

  // ── Generation provenance ──────────────────────────────────────────────────
  /// Display name or ID of the user who triggered the export.
  final String reportGeneratedBy;

  /// UTC timestamp when the export was generated. INV-3: always UTC.
  final DateTime reportGeneratedAtUtc;

  // ── Platform version metadata ──────────────────────────────────────────────
  final String engineVersion;
  final String platformVersion;

  const AttestationHeader._({
    required this.tenantName,
    required this.tenantCnpj,
    required this.contractorName,
    required this.contractorCnpj,
    required this.reportGeneratedBy,
    required this.reportGeneratedAtUtc,
    required this.engineVersion,
    required this.platformVersion,
  });

  factory AttestationHeader.create({
    required String tenantName,
    required String? tenantCnpj,
    required String contractorName,
    required String? contractorCnpj,
    required String reportGeneratedBy,
    required DateTime reportGeneratedAtUtc,
    required String engineVersion,
    String platformVersion = 'PactaFlow 7.1',
  }) {
    if (tenantName.trim().isEmpty) {
      throw const DomainException('tenantName must not be empty');
    }
    if (contractorName.trim().isEmpty) {
      throw const DomainException('contractorName must not be empty');
    }
    if (reportGeneratedBy.trim().isEmpty) {
      throw const DomainException('reportGeneratedBy must not be empty');
    }
    if (!reportGeneratedAtUtc.isUtc) {
      throw const DomainException(
        'reportGeneratedAtUtc must be UTC (INV-3). Call .toUtc() before passing.',
      );
    }
    if (engineVersion.trim().isEmpty) {
      throw const DomainException('engineVersion must not be empty');
    }

    return AttestationHeader._(
      tenantName: tenantName,
      tenantCnpj: tenantCnpj,
      contractorName: contractorName,
      contractorCnpj: contractorCnpj,
      reportGeneratedBy: reportGeneratedBy,
      reportGeneratedAtUtc: reportGeneratedAtUtc,
      engineVersion: engineVersion,
      platformVersion: platformVersion,
    );
  }

  factory AttestationHeader.reconstitute({
    required String tenantName,
    required String? tenantCnpj,
    required String contractorName,
    required String? contractorCnpj,
    required String reportGeneratedBy,
    required DateTime reportGeneratedAtUtc,
    required String engineVersion,
    required String platformVersion,
  }) {
    return AttestationHeader._(
      tenantName: tenantName,
      tenantCnpj: tenantCnpj,
      contractorName: contractorName,
      contractorCnpj: contractorCnpj,
      reportGeneratedBy: reportGeneratedBy,
      reportGeneratedAtUtc: reportGeneratedAtUtc,
      engineVersion: engineVersion,
      platformVersion: platformVersion,
    );
  }

  /// Canonical legal notice printed in every exported document.
  ///
  /// References CPC Art. 369–376 for Brazilian documentary evidence compliance.
  String get legalNotice =>
      'Documento gerado automaticamente pelo sistema $platformVersion. '
      'Os dados apresentados são extraídos de registros imutáveis armazenados '
      'em banco de dados com regras de não-alteração e não-exclusão em nível de BD. '
      'O hash SHA-256 deste relatório pode ser verificado de forma independente '
      'conforme CPC Art. 369–376.';

  /// Immutability statement printed in every exported document.
  String get immutabilityStatement =>
      'GARANTIA DE IMUTABILIDADE: Registros são append-only. '
      'Regras de banco de dados bloqueiam UPDATE/DELETE independentemente do '
      'código da aplicação. Row Level Security garante isolamento por tenant via '
      'claims JWT de organização.';

  /// Independent verification instructions for auditors.
  String verificationInstructions({
    required String organizationId,
    required String contractScope,
    required String periodStart,
    required String periodEnd,
  }) =>
      'VERIFICAÇÃO INDEPENDENTE: Recalcule SHA-256 da string '
      '"$organizationId|$contractScope|$periodStart|$periodEnd" '
      'e compare com o Package Hash acima. '
      'Correspondência = conteúdo não modificado desde a geração.';

  @override
  List<Object?> get props => [
    tenantName,
    tenantCnpj,
    contractorName,
    contractorCnpj,
    reportGeneratedBy,
    reportGeneratedAtUtc,
    engineVersion,
    platformVersion,
  ];
}
