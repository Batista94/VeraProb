/// Command to seal a verdict into the Forensic Evidence Vault.
///
/// Carries no SLA rule content — the Backend Authority resolves the active rule
/// from the database (Req 5). [idempotencyKey] makes a retry return the existing
/// snapshot instead of creating a second verdict (Req 6/10.4).
class SealForensicEvidenceCommand {
  final String organizationId;
  final String sessionId;
  final String contractId;
  final String setId;
  final String verdictType;
  final int planVersion;
  final DateTime occurredAtUtc;
  final String sealedBy;
  final String idempotencyKey;

  const SealForensicEvidenceCommand({
    required this.organizationId,
    required this.sessionId,
    required this.contractId,
    required this.setId,
    required this.verdictType,
    required this.planVersion,
    required this.occurredAtUtc,
    required this.sealedBy,
    required this.idempotencyKey,
  });
}
