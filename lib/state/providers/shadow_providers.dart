import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/ad_hoc_cost/shadow_execution_summary.dart';
import 'package:veraprob/infrastructure/ad_hoc_cost/postgres_shadow_execution_repository.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/state/provider_timeout.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

final shadowRepoProvider = Provider<PostgresShadowExecutionRepository>((ref) {
  return PostgresShadowExecutionRepository(ref.watch(supabaseClientProvider));
});

/// Unlinked shadow executions for current org. INV-1: org-scoped.
final unlinkedShadowsProvider =
    FutureProvider.autoDispose<List<ShadowExecutionSummary>>((ref) async {
      final orgId = ref.watch(currentOrganizationIdProvider);
      if (orgId == null) return [];
      final entities = await ref
          .watch(shadowRepoProvider)
          .findUnlinked(organizationId: orgId)
          .withProviderTimeout();
      return entities.map(ShadowExecutionSummary.fromDomain).toList();
    });

/// Smart Link candidates: execution_states whose time window overlaps
/// shadow's message_ts ±30min. Returns list of {set_id, window_start_utc}.
final smartLinkCandidatesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, ShadowExecutionSummary>((
      ref,
      shadow,
    ) async {
      final orgId = ref.watch(currentOrganizationIdProvider);
      if (orgId == null) return [];

      return ref
          .watch(shadowRepoProvider)
          .findSmartLinkCandidates(
            organizationId: orgId,
            messageTs: shadow.messageTs,
          )
          .withProviderTimeout();
    });
