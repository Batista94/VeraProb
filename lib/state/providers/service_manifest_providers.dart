import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/domain/sla_audit/service_manifest.dart';
import 'package:veraprob/domain/sla_audit/service_manifest_repository.dart';
import 'package:veraprob/infrastructure/persistence/persistence_mode.dart';
import 'package:veraprob/infrastructure/persistence/persistence_provider.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_service_manifest_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_service_manifest_repository.dart';
import 'auth_providers.dart';

// ── Repository ───────────────────────────────────────────────

final serviceManifestRepositoryProvider = Provider<ServiceManifestRepository>((
  ref,
) {
  return switch (ref.watch(persistenceModeProvider)) {
    PersistenceMode.inMemory => InMemoryServiceManifestRepository(),
    PersistenceMode.postgres => PostgresServiceManifestRepository(
      ref.watch(supabaseClientProvider),
    ),
  };
});

// ── Manifests by contract ────────────────────────────────────

/// All [ServiceManifest]s for a given contract, ordered by name.
final serviceManifestsByContractProvider =
    FutureProvider.family<List<ServiceManifest>, String>((
      ref,
      contractId,
    ) async {
      final orgId = ref.watch(currentOrganizationIdProvider);
      if (orgId == null) return const [];

      return ref
          .watch(serviceManifestRepositoryProvider)
          .findByContract(contractId, organizationId: orgId);
    });

// ── Mutations ────────────────────────────────────────────────

/// Saves a manifest and invalidates the relevant contract cache.
Future<void> saveServiceManifest(
  ServiceManifest manifest,
  WidgetRef ref,
) async {
  await ref.read(serviceManifestRepositoryProvider).save(manifest);
  ref.invalidate(serviceManifestsByContractProvider);
}

/// Deletes a manifest and invalidates the relevant contract cache.
Future<void> deleteServiceManifest(
  String manifestId,
  String organizationId,
  WidgetRef ref,
) async {
  await ref
      .read(serviceManifestRepositoryProvider)
      .delete(manifestId, organizationId: organizationId);
  ref.invalidate(serviceManifestsByContractProvider);
}
