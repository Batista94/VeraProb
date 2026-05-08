import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/sla_audit/local_sync_orchestrator.dart';
import 'package:veraprob/domain/sla_audit/local_fact_queue/chain_integrity_verifier.dart';
import 'package:veraprob/domain/sla_audit/local_fact_queue/local_fact_queue_repository.dart';
import 'package:veraprob/domain/sla_audit/local_fact_queue/sync_handshake_service.dart';
import 'package:veraprob/infrastructure/local_fact_db/drift_local_fact_queue_repository.dart';
import 'package:veraprob/infrastructure/local_fact_db/in_memory_local_fact_queue_repository.dart';
import 'package:veraprob/infrastructure/local_fact_db/local_fact_database.dart';
import 'package:veraprob/infrastructure/local_fact_db/supabase_sync_handshake_service.dart';
import 'package:veraprob/infrastructure/persistence/persistence_mode.dart';
import 'package:veraprob/infrastructure/persistence/persistence_provider.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/state/notifiers/connectivity_notifier.dart';
import 'package:veraprob/state/providers/shared_providers.dart';

// ── Database singleton ────────────────────────────────────────────────────────

/// Singleton drift database — WasmDatabase on Flutter Web, native SQLite
/// on other platforms (handled automatically by drift_flutter).
final localFactDatabaseProvider = Provider<LocalFactDatabase>((ref) {
  final db = LocalFactDatabase();
  ref.onDispose(db.close);
  return db;
});

// ── Repository ────────────────────────────────────────────────────────────────

/// Provides the [LocalFactQueueRepository] scoped to the current persistence mode.
///
/// Uses [InMemoryLocalFactQueueRepository] in tests (`PersistenceMode.inMemory`)
/// and [DriftLocalFactQueueRepository] in production (`PersistenceMode.postgres`).
final localFactQueueRepositoryProvider = Provider<LocalFactQueueRepository>((
  ref,
) {
  return switch (ref.watch(persistenceModeProvider)) {
    PersistenceMode.inMemory => InMemoryLocalFactQueueRepository(
      ref.watch(dateTimeProviderProvider),
    ),
    PersistenceMode.postgres => DriftLocalFactQueueRepository(
      ref.watch(localFactDatabaseProvider),
      ref.watch(dateTimeProviderProvider),
    ),
  };
});

// ── Handshake service ─────────────────────────────────────────────────────────

final syncHandshakeServiceProvider = Provider<SyncHandshakeService>((ref) {
  return SupabaseSyncHandshakeService(ref.watch(supabaseClientProvider));
});

// ── Orchestrator ──────────────────────────────────────────────────────────────

/// Central orchestrator for the Edge Ledger sync lifecycle.
final localSyncOrchestratorProvider = Provider<LocalSyncOrchestrator>((ref) {
  return LocalSyncOrchestrator(
    queue: ref.watch(localFactQueueRepositoryProvider),
    handshake: ref.watch(syncHandshakeServiceProvider),
    verifier: const ChainIntegrityVerifier(),
  );
});

// ── Reactive badge count ──────────────────────────────────────────────────────

/// Emits the total number of buffered facts (all statuses).
/// Used by [EdgeLedgerStatusBadge] to render Synced / N buffered states.
final pendingFactCountProvider = StreamProvider<int>((ref) {
  return ref.watch(localFactQueueRepositoryProvider).watchPendingCount();
});

// ── Connectivity watcher ──────────────────────────────────────────────────────

/// Watches Supabase auth events and triggers [LocalSyncOrchestrator.onConnectionRestored]
/// on reconnect, filling any sequence gaps in the local fact queue.
final connectivityNotifierProvider =
    NotifierProvider.autoDispose<
      ConnectivityNotifier,
      EdgeLedgerConnectionState
    >(ConnectivityNotifier.new);
