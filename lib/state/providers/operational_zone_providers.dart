import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/sla_audit/operational_zone.dart';
import '../../domain/sla_audit/operational_zone_repository.dart';
import '../../infrastructure/persistence/persistence_mode.dart';
import '../../infrastructure/persistence/persistence_provider.dart';
import '../../infrastructure/providers/supabase_provider.dart';
import '../../infrastructure/sla_audit/in_memory_operational_zone_repository.dart';
import '../../infrastructure/sla_audit/postgres_operational_zone_repository.dart';
import 'auth_providers.dart';

// ── Repository ───────────────────────────────────────────────

final operationalZoneRepositoryProvider = Provider<OperationalZoneRepository>((
  ref,
) {
  return switch (ref.watch(persistenceModeProvider)) {
    PersistenceMode.inMemory => InMemoryOperationalZoneRepository(),
    PersistenceMode.postgres => PostgresOperationalZoneRepository(
      ref.watch(supabaseClientProvider),
    ),
  };
});

// ── Zone list ────────────────────────────────────────────────

/// All [OperationalZone]s for the current organization.
final operationalZonesProvider = FutureProvider<List<OperationalZone>>((
  ref,
) async {
  final orgId = ref.watch(currentOrganizationIdProvider);
  if (orgId == null) return const [];

  return ref.watch(operationalZoneRepositoryProvider).findByOrganization(orgId);
});

// ── Create zone ──────────────────────────────────────────────

/// Saves a zone and invalidates the list cache.
Future<void> saveZone(OperationalZone zone, WidgetRef ref) async {
  await ref.read(operationalZoneRepositoryProvider).save(zone);
  ref.invalidate(operationalZonesProvider);
}
