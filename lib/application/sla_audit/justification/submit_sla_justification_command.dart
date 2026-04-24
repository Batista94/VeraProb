/// Command to submit a new SLA justification for a vehicle infraction event.
///
/// The [vehicleId] + [occurrenceTimestamp] pair forms the forensic anchor
/// linking this justification to the original `VehicleOperationalState`
/// detected by the Normalizer (CX-04).
///
/// [evidenceHashes] are SHA-256 hex digests computed from the raw file
/// bytes BEFORE upload to Supabase Storage (CX05-INV-23). The client
/// computes the hash when reading the image buffer from disk, eliminating
/// latency from post-upload re-fetching.
class SubmitSLAJustificationCommand {
  final String organizationId;
  final String sessionId;
  final String vehicleId;
  final DateTime occurrenceTimestamp;
  final String category;
  final String description;
  final List<String> evidenceUrls;
  final List<String> evidenceHashes;
  final String callerUserId;

  const SubmitSLAJustificationCommand({
    required this.organizationId,
    required this.sessionId,
    required this.vehicleId,
    required this.occurrenceTimestamp,
    required this.category,
    required this.description,
    required this.evidenceUrls,
    required this.evidenceHashes,
    required this.callerUserId,
  });
}
