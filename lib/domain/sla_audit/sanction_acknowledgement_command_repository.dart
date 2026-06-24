/// Port (INV-13) for recording an off-band sanction acknowledgement
/// ("De Acordo interno"), backed by the `acknowledge_sanction_internal`
/// SECURITY DEFINER RPC.
///
/// Atomicity + authority live in the DB transaction: the RPC row-locks the
/// queue entry, re-checks `applied` status, inserts the `INTERNAL_RECORD`
/// acknowledgement, flips the queue to the terminal `acknowledged` status, and
/// appends a `SANCTION_ACKNOWLEDGED` ledger fact (INV-3) — and enforces
/// TENANT_ADMIN authority server-side.
///
/// The carrier-facing ("De Acordo via portal") path is intentionally NOT here:
/// it is anon and lives in the dispute-portal gateway.
// pr_scanner: ignore-regression — new additive port (Council-approved Sprint A plan)
abstract class SanctionAcknowledgementCommandRepository {
  /// Records an internal acknowledgement for an applied sanction. Returns the
  /// new acknowledgement id. Throws a mapped domain exception on a non-applied
  /// state or insufficient authority (opaque, INV-26).
  Future<String> acknowledgeInternal({
    required String organizationId,
    required String queueEntryId,
    required String acknowledgedByUserId,
    String? notes,
  });
}
