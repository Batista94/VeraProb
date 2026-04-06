import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/admin/operational_zone_view.dart';
import '../../domain/sla_audit/operational_zone_repository.dart';
import '../../infrastructure/persistence/persistence_mode.dart';
import '../../infrastructure/persistence/persistence_provider.dart';
import '../../infrastructure/providers/supabase_provider.dart';
import '../../infrastructure/sla_audit/in_memory_operational_zone_repository.dart';
import '../../infrastructure/sla_audit/postgres_operational_zone_repository.dart';
import '../../domain/sla_audit/geocoding_repository.dart';
import '../../infrastructure/sla_audit/http_geocoding_repository.dart';
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

/// All [OperationalZoneView]s for the current organization.
final operationalZonesProvider = FutureProvider<List<OperationalZoneView>>((
  ref,
) async {
  final orgId = ref.watch(currentOrganizationIdProvider);
  if (orgId == null) return <OperationalZoneView>[];

  final zones = await ref
      .watch(operationalZoneRepositoryProvider)
      .findByOrganization(orgId);
  return zones.map(OperationalZoneView.fromDomain).toList();
});

// ── Create zone ──────────────────────────────────────────────

/// Saves a zone and invalidates the list cache.
Future<void> saveZone(OperationalZoneView zone, WidgetRef ref) async {
  await ref.read(operationalZoneRepositoryProvider).save(zone.toDomain());
  ref.invalidate(operationalZonesProvider);
}

// ── Geocoding ────────────────────────────────────────────────

final geocodingRepositoryProvider = Provider<GeocodingRepository>((ref) {
  return HttpGeocodingRepository();
});

/// Performs a geocoding search for the given query.
final geocodingSearchProvider =
    FutureProvider.family<List<PlaceSuggestion>, String>((ref, query) async {
      if (query.length < 4) return <PlaceSuggestion>[];
      // Artificial delay to mimic debouncing is handled by Riverpod's cache
      return ref.watch(geocodingRepositoryProvider).search(query);
    });
