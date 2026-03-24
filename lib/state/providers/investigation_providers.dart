import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/sla_audit/evaluation_trace.dart';
import '../../domain/sla_audit/sla_ledger_entry.dart';
import '../../domain/sla_audit/contractual_execution_state.dart';
import 'auth_providers.dart';
import 'sla_providers.dart';

/// Retrieves all evaluation traces for a given entity (SET ID).
/// Returns an empty list if no traces exist (pre-Phase 3 records).
final evaluationTracesProvider =
    FutureProvider.family<List<EvaluationTrace>, String>((ref, entityId) async {
      final traceRepo = ref.watch(evaluationTraceRepositoryProvider);
      return traceRepo.findByEntityId(entityId);
    });

/// Retrieves all ledger entries for a given SET ID.
/// Always returns entries sorted chronologically by occurredAtUtc.
final ledgerEntriesProvider =
    FutureProvider.family<List<SlaLedgerEntry>, String>((ref, setId) async {
      final organizationId = ref.watch(currentOrganizationIdProvider);
      if (organizationId == null) return [];
      final ledgerRepo = ref.watch(slaAuditLedgerRepositoryProvider);
      final entries = await ledgerRepo.getEntriesBySetId(
        setId,
        organizationId: organizationId,
      );
      // Enforce chronological order regardless of repository implementation
      entries.sort((a, b) => a.occurredAtUtc.compareTo(b.occurredAtUtc));
      return entries;
    });

/// Retrieves a specific execution state for forensic analysis.
final executionStateProvider =
    FutureProvider.family<ContractualExecutionState?, String>((
      ref,
      setId,
    ) async {
      final repo = ref.watch(contractualExecutionStateRepositoryProvider);
      return repo.findBySetId(setId);
    });
