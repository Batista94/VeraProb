import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../state/providers/authority_providers.dart';
import '../../../domain/authority/repositories/in_memory_forensic_repository.dart';
import '../../../domain/authority/decision/authorization_decision.dart';
import '../../../infrastructure/authority/postgres_forensic_ledger_projection.dart';
import '../../../infrastructure/persistence/persistence_mode.dart';
import '../../../infrastructure/persistence/persistence_provider.dart';
import '../../../infrastructure/providers/supabase_provider.dart';
import '../models/forensic_ledger_entry.dart';

/// Builds a narrative sentence from an [AuthorizationDecision].
///
/// This lives in the **Projection Layer** — never in the Domain or UI.
/// It translates raw domain events into human-readable operator language.
String toNarrative(AuthorizationDecision d) {
  final actor = d.actorId.value;
  final action = _actionVerb(d.actionType.key);
  final result = d.result.name == 'approved' ? '' : ' (NEGADO)';
  final reason = (d.reason != null && d.reason!.isNotEmpty)
      ? ': ${d.reason}'
      : '';

  return '$actor $action$reason$result';
}

/// Maps action keys to Portuguese narrative verbs/phrases.
String _actionVerb(String key) {
  const verbs = <String, String>{
    'resolve_alert': 'resolveu alerta',
    'manual_status_override': 'ajustou status manualmente',
    'reassign_vehicle': 'realocou veículo',
    'override_route_deviation': 'autorizou desvio de rota',
    'update_trip_status': 'alterou status de viagem',
    'create_incident': 'registrou ocorrência',
    'cancel_trip': 'cancelou viagem',
    'dispatch_trip': 'despachou viagem',
    'regularize_trip': 'autorizou regularização',
    'interrupt_trip': 'interrompeu viagem',
  };
  return verbs[key] ?? key.replaceAll('_', ' ');
}

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
                  actionLabel: _actionVerb(d.actionType.key),
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
