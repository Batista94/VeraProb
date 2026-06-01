import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot.dart';
import 'package:veraprob/domain/sla_audit/forensic_evidence_snapshot_repository.dart';
import 'seal_forensic_evidence_command.dart';

/// Application handler for [SealForensicEvidenceCommand].
///
/// Thin orchestrator: enforces tenant identity (INV-1 fail-fast) then delegates
/// to the Backend-Authority RPC via the repository, which performs the atomic
/// verdict-append + snapshot-seal + hash in one transaction (Req 5/10).
/// Idempotency is guaranteed by the database on (organizationId, idempotencyKey)
/// — no application-side store is required.
class SealForensicEvidenceHandler {
  final TenantValidationService _tenantValidator;
  final ForensicEvidenceSnapshotRepository _vault;

  SealForensicEvidenceHandler({
    required TenantValidationService tenantValidator,
    required ForensicEvidenceSnapshotRepository vault,
  }) : _tenantValidator = tenantValidator,
       _vault = vault;

  /// Seals the verdict and returns its forensic snapshot.
  ///
  /// Throws [DomainException] on tenant mismatch, empty identifiers, or a
  /// non-UTC verdict timestamp (INV-6).
  Future<ForensicEvidenceSnapshot> handle(
    SealForensicEvidenceCommand command,
  ) async {
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    if (command.contractId.trim().isEmpty) {
      throw const DomainException('contractId must not be empty');
    }
    if (command.idempotencyKey.trim().isEmpty) {
      throw const DomainException('idempotencyKey must not be empty (INV-11)');
    }
    if (!command.occurredAtUtc.isUtc) {
      throw const DomainException(
        'occurredAtUtc must be UTC (INV-6). Call .toUtc() before sealing.',
      );
    }

    return _vault.seal(
      organizationId: command.organizationId,
      contractId: command.contractId,
      setId: command.setId,
      verdictType: command.verdictType,
      planVersion: command.planVersion,
      occurredAtUtc: command.occurredAtUtc,
      sealedBy: command.sealedBy,
      idempotencyKey: command.idempotencyKey,
    );
  }
}
