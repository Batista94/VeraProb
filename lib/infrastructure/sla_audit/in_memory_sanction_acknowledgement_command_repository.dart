import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_acknowledgement_command_repository.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';

/// In-memory mirror of `acknowledge_sanction_internal`: look up (locked) →
/// `applied` re-check → `SANCTION_ACKNOWLEDGED` ledger append → terminal
/// `acknowledged` flip. Same atomic semantics as Postgres for handler tests
/// and the in-memory persistence mode.
class InMemorySanctionAcknowledgementCommandRepository
    implements SanctionAcknowledgementCommandRepository {
  InMemorySanctionAcknowledgementCommandRepository({
    required SanctionReviewQueueRepository queueRepo,
    required SlaAuditLedgerRepository ledger,
    IDateTimeProvider? clock,
  }) : _queue = queueRepo,
       _ledger = ledger,
       _clock = clock ?? BrazilDateTimeProvider();

  final SanctionReviewQueueRepository _queue;
  final SlaAuditLedgerRepository _ledger;
  final IDateTimeProvider _clock;

  @override
  Future<String> acknowledgeInternal({
    required String organizationId,
    required String queueEntryId,
    required String acknowledgedByUserId,
    String? notes,
  }) async {
    final entry = await _queue.findById(
      queueEntryId,
      organizationId: organizationId,
    );
    // Mirror the RPC anti-oracle posture (42501) for missing / wrong-org / state.
    if (entry == null || entry.status != SanctionReviewStatus.applied) {
      throw const DomainException('Acknowledgement rejected.');
    }

    final occurredAtUtc = _clock.nowUtc();
    final ledgerEntryId = await _ledger.append(
      SlaLedgerEntry(
        organizationId: organizationId,
        type: 'SANCTION_ACKNOWLEDGED',
        operatorId: acknowledgedByUserId,
        setId: entry.setId,
        contractId: entry.contractId,
        planVersion: 0,
        occurredAtUtc: occurredAtUtc,
        payload: {
          'queue_entry_id': queueEntryId,
          'method': 'INTERNAL_RECORD',
          'acknowledged_by': acknowledgedByUserId,
          'notes': notes,
        },
      ),
    );

    await _queue.updateStatus(
      entry.copyWith(status: SanctionReviewStatus.acknowledged),
    );

    return ledgerEntryId;
  }
}
