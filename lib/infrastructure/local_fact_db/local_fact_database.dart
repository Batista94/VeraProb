import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../domain/sla_audit/local_fact_queue/pending_fact.dart'
    as domain
    show PendingFact;
import '../../domain/sla_audit/local_fact_queue/sync_status.dart';

part 'local_fact_database.g.dart';

// ── Table definition ─────────────────────────────────────────────────────────

class PendingFacts extends Table {
  TextColumn get factId => text()();
  TextColumn get organizationId => text()();
  TextColumn get contentHash => text().unique()();
  TextColumn get factPayloadJson => text()();
  DateTimeColumn get receivedAtUtc => dateTime()();
  DateTimeColumn get queuedAtUtc => dateTime()();
  TextColumn get syncStatus => text()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get errorMessage => text().nullable()();
  IntColumn get localSequence => integer()();

  @override
  Set<Column> get primaryKey => {factId};
}

// ── Database ──────────────────────────────────────────────────────────────────

@DriftDatabase(tables: [PendingFacts])
class LocalFactDatabase extends _$LocalFactDatabase {
  LocalFactDatabase([QueryExecutor? executor])
    : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration =>
      MigrationStrategy(onCreate: (m) => m.createAll());

  static QueryExecutor _openConnection() =>
      driftDatabase(name: 'edge_ledger_v1');
}

// ── Mapper helpers ────────────────────────────────────────────────────────────

/// Converts a drift row (generated [PendingFact]) to the domain
/// [domain.PendingFact] value object.
extension DriftRowToDomain on PendingFact {
  domain.PendingFact toDomain() => domain.PendingFact.reconstitute(
    factId: factId,
    organizationId: organizationId,
    contentHash: contentHash,
    factPayloadJson: factPayloadJson,
    receivedAtUtc: receivedAtUtc,
    queuedAtUtc: queuedAtUtc,
    syncStatus: SyncStatus.values.firstWhere(
      (s) => s.name == syncStatus,
      orElse: () => SyncStatus.pending,
    ),
    localSequence: localSequence,
    retryCount: retryCount,
    errorMessage: errorMessage,
  );
}

/// Converts the domain [domain.PendingFact] to a drift [PendingFactsCompanion]
/// for INSERT operations.
extension DomainToCompanion on domain.PendingFact {
  PendingFactsCompanion toCompanion() => PendingFactsCompanion.insert(
    factId: factId,
    organizationId: organizationId,
    contentHash: contentHash,
    factPayloadJson: factPayloadJson,
    receivedAtUtc: receivedAtUtc,
    queuedAtUtc: queuedAtUtc,
    syncStatus: syncStatus.name,
    retryCount: Value(retryCount),
    errorMessage: Value(errorMessage),
    localSequence: localSequence,
  );
}
