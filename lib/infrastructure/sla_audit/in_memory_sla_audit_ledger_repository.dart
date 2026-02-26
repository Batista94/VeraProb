import 'package:flutter/foundation.dart';

import '../../domain/sla_audit/domain_event.dart';
import '../../domain/sla_audit/sla_audit_ledger_repository.dart';

/// In-memory append-only implementation of [SlaAuditLedgerRepository].
///
/// Stores events in memory and prints to console in debug mode.
/// Follows the same pattern as [InMemoryForensicRepository] from the
/// Trust Backbone, but is intentionally separate.
class InMemorySlaAuditLedgerRepository implements SlaAuditLedgerRepository {
  final List<DomainEvent> _ledger = [];

  /// Read-only view of all appended events (for testing).
  @visibleForTesting
  List<DomainEvent> get entries => List.unmodifiable(_ledger);

  @override
  Future<void> append(DomainEvent event) async {
    _ledger.add(event);

    if (kDebugMode) {
      print(
        '[SLA AUDIT LEDGER] Event appended: '
        '${event.runtimeType} at ${event.occurredAtUtc.toIso8601String()}',
      );
    }
  }
}
