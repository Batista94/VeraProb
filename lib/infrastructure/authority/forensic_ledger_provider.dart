import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/projections/forensic_ledger_view.dart';
import 'package:veraprob/domain/authority/repositories/in_memory_forensic_repository.dart';
import 'package:veraprob/infrastructure/authority/postgres_forensic_ledger_projection.dart';
import 'package:veraprob/infrastructure/persistence/persistence_mode.dart';
import 'package:veraprob/infrastructure/persistence/persistence_provider.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/state/providers/authority_providers.dart';

/// Projection Provider for the Forensic Ledger.
///
/// Listens to the append-only forensic repository and projects Domain entities
/// into safe, structured DTOs ([ForensicLedgerEntry]) with narrative text,
/// sorted in reverse-chronological order (newest first).
final forensicLedgerProjectionProvider =
    StreamProvider<List<ForensicLedgerEntry>>((ref) {
      final mode = ref.watch(persistenceModeProvider);

      if (mode == PersistenceMode.postgres) {
        final client = ref.watch(supabaseClientProvider);
        return PostgresForensicLedgerProjection(client).watchLedger();
      }

      final repo = ref.watch(forensicDecisionRepositoryProvider);

      if (repo is InMemoryForensicRepository) {
        return repo.ledgerStream.map((decisions) {
          return decisions.reversed
              .map(
                (d) => ForensicLedgerEntry(
                  decisionId: d.decisionId,
                  actionType: d.actionType.key,
                  actionLabel: actionVerb(d.actionType.key),
                  actorId: d.actorId.value,
                  result: d.result.name.toUpperCase(),
                  reason: d.reason,
                  narrative: toNarrative(d),
                  timestamp: d.occurredAt,
                ),
              )
              .toList();
        });
      }

      return Stream.value([]);
    });
