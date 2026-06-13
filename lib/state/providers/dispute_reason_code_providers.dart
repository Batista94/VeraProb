// pr_scanner: ignore-regression
// Council-reviewed (Phase 10.6 v3 council-remediated plan, 2026-06-12):
// dispute reality core — evidence/reason-code/command contracts (INV-1/3/9).
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/domain/sla_audit/dispute_reason_code.dart';
import 'package:veraprob/infrastructure/sla_audit/sla_persistence_provider.dart';
import 'auth_providers.dart';

/// Async catalogue of active dispute reason codes (Componente 4.5).
///
/// Read-only global taxonomy (Q2): session-cached (NOT autoDispose) so every
/// open dropdown shares a single `findAllActive()` fetch instead of re-querying
/// on each card rebuild. RLS scopes the result to global + own-org codes;
/// [currentOrganizationIdProvider] is threaded for forward-compatibility with
/// the future custom-codes phase (the v1 repo returns only global codes).
final disputeReasonCodesProvider = FutureProvider<List<DisputeReasonCode>>((
  ref,
) async {
  final orgId = ref.watch(currentOrganizationIdProvider);
  final repo = ref.watch(disputeReasonCodeRepositoryProvider);
  return repo.findAllActive(organizationId: orgId);
});
