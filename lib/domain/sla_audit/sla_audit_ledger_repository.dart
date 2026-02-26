import 'domain_event.dart';

/// Domain Port: Append-only ledger for SLA Audit domain events.
///
/// This port belongs exclusively to the `sla_audit` subdomain.
/// It is intentionally separate from the Trust Backbone's
/// [ForensicDecisionRepository], which handles [AuthorizationDecision]s.
///
/// Implementations must guarantee append-only semantics.
abstract class SlaAuditLedgerRepository {
  /// Appends a domain event to the ledger.
  Future<void> append(DomainEvent event);
}
