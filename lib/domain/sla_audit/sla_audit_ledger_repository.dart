import 'sla_ledger_entry.dart';

/// Domain Port: Append-only ledger for SLA Audit forensic entries.
///
/// This port belongs exclusively to the `sla_audit` subdomain.
/// It is intentionally separate from the Trust Backbone's
/// [ForensicDecisionRepository], which handles [AuthorizationDecision]s.
///
/// Implementations must guarantee append-only semantics and monotonic ordering.
abstract class SlaAuditLedgerRepository {
  /// Appends a forensic entry to the ledger.
  /// Returns the generated event UUID for causal linkage.
  Future<String> append(SlaLedgerEntry entry);

  /// Retrieves the sequence ID of the most recent entry in the ledger.
  /// Used to deterministically capture the causal boundary of a financial closure.
  Future<String?> getLastEntryId();

  /// Retrieves all forensic entries related to a specific contractual or operational set (e.g. trip).
  /// Ordered chronologically.
  Future<List<SlaLedgerEntry>> getEntriesBySetId(String setId);
}
