import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../state/providers/authority_providers.dart';
import '../../../domain/authority/repositories/in_memory_forensic_repository.dart';
import '../models/forensic_ledger_entry.dart';

/// Projection Provider for the Forensic Ledger.
///
/// It listens to the append-only storage and projects Domain entities
/// into safe, structured DTOs ([ForensicLedgerEntry]) for the UI,
/// sorted in reverse-chronological order (newest first).
final forensicLedgerProjectionProvider =
    StreamProvider<List<ForensicLedgerEntry>>((ref) {
      final repo = ref.watch(forensicDecisionRepositoryProvider);

      if (repo is InMemoryForensicRepository) {
        return repo.ledgerStream.map((decisions) {
          return decisions.reversed
              .map(
                (d) => ForensicLedgerEntry(
                  decisionId: d.decisionId,
                  actionType: d.actionType.key,
                  actorId: d.actorId.value,
                  result: d.result.name.toUpperCase(),
                  timestamp: d.occurredAt,
                ),
              )
              .toList();
        });
      }

      return Stream.value([]);
    });
