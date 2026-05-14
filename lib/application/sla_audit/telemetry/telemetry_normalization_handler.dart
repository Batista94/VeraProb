import 'package:veraprob/application/intelligence/ping_classification.dart';
import 'package:veraprob/application/intelligence/telemetry_normalizer.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/telemetry/normalization_outcome.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/entities/raw_telemetry_ping.dart';
import 'package:veraprob/domain/sla_audit/canonical_fact.dart';
import 'package:veraprob/domain/sla_audit/ingestion_integrity_flag.dart';
import 'package:veraprob/domain/sla_audit/spoofing_detector.dart';
import 'package:veraprob/domain/sla_audit/telemetry/spoofing_detected_exception.dart';
import 'package:veraprob/domain/sla_audit/telemetry/raw_telemetry_batch.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';

/// Final processing stage before persistence/Engine dispatch.
///
/// [normalize] is a linear pipeline ("Caminho do Pacote"): each stage is a
/// named private method, keeping every function < 50 LOC and the orchestrator
/// cyclomatic complexity near 1.
class TelemetryNormalizationHandler {
  final TelemetryNormalizer normalizer;
  final SlaLedgerRepository ledgerRepository;
  final FactQueue factQueue;
  final IDateTimeProvider _clock;
  final TenantValidationService _tenantValidator;
  final SpoofingDetector _spoofingDetector;

  TelemetryNormalizationHandler({
    required this.normalizer,
    required this.ledgerRepository,
    required this.factQueue,
    required IDateTimeProvider clock,
    required TenantValidationService tenantValidator,
    required SpoofingDetector spoofingDetector,
  }) : _clock = clock,
       _tenantValidator = tenantValidator,
       _spoofingDetector = spoofingDetector;

  /// Normalizes a raw telemetry batch through the ingestion pipeline.
  ///
  /// Returns a [NormalizationOutcome] with the accepted-vs-rejected breakdown.
  /// Throws [SpoofingDetectedException] if a spoofing gate quarantines the
  /// batch — the forensic ledger entry is written by the gate before throwing.
  Future<NormalizationOutcome> normalize(
    RawTelemetryBatch batch, {
    required String sessionId,
  }) async {
    await _assertTenantSovereignty(batch, sessionId);
    final pings = _unpackBatch(batch);
    await _assertBatchVariance(pings, batch);
    final outcome = _normalizeBatch(pings, batch);
    final deviceBatches = _organizeChronologically(outcome.acceptedFacts);
    await _screenForSpoofing(deviceBatches, batch);
    await _recordRejections(outcome, batch);
    _dispatchToEngine(outcome.acceptedFacts);
    return outcome;
  }

  /// Stage 1 — INV-1: fail-fast tenant sovereignty check before any I/O.
  Future<void> _assertTenantSovereignty(
    RawTelemetryBatch batch,
    String sessionId,
  ) async {
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: batch.organizationId,
      sessionId: sessionId,
    );
  }

  /// Stage 2 — unpacks the batch's coordinates into raw telemetry pings.
  List<RawTelemetryPing> _unpackBatch(RawTelemetryBatch batch) {
    return batch.coordinates
        .map(
          (coord) => RawTelemetryPing(
            vehicleId: batch.deviceId,
            tripId: '',
            latitude: coord.latitude,
            longitude: coord.longitude,
            heading: 0.0,
            speed: 0.0,
            accuracy: 10.0,
            timestamp: coord.occurredAt,
          ),
        )
        .toList();
  }

  /// Stage 3 — INV-18: zero-variance synthetic-pattern gate.
  /// Writes the forensic record at the source before rethrowing.
  Future<void> _assertBatchVariance(
    List<RawTelemetryPing> pings,
    RawTelemetryBatch batch,
  ) async {
    try {
      normalizer.validateBatch(pings, batch.deviceId);
    } on SpoofingDetectedException catch (e) {
      await _recordSpoofingForensic(
        batch,
        deviceId: e.deviceId,
        reason: e.reason,
        batchSize: batch.coordinates.length,
      );
      rethrow;
    }
  }

  /// Stage 4 — per-item normalization. One corrupt ping cannot abort the batch.
  NormalizationOutcome _normalizeBatch(
    List<RawTelemetryPing> pings,
    RawTelemetryBatch batch,
  ) {
    final accepted = <CanonicalFact>[];
    final rejected = <RejectedPacket>[];

    for (var i = 0; i < pings.length; i++) {
      final result = _normalizeSinglePing(pings[i], i, batch);
      if (result.fact != null) {
        accepted.add(result.fact!);
      } else if (result.rejected != null) {
        rejected.add(result.rejected!);
      }
    }

    return NormalizationOutcome(
      acceptedFacts: accepted,
      rejectedPackets: rejected,
    );
  }

  /// Batch evaluator — classifies a single ping, isolating failures (INV-10).
  ({CanonicalFact? fact, RejectedPacket? rejected}) _normalizeSinglePing(
    RawTelemetryPing ping,
    int index,
    RawTelemetryBatch batch,
  ) {
    try {
      final classification = normalizer.classifyPing(ping);
      if (classification is PingRejected) {
        return (
          fact: null,
          rejected: RejectedPacket(
            batchIndex: index,
            reason: classification.reason.name,
          ),
        );
      }
      return (fact: _toCanonicalFact(ping, batch), rejected: null);
    } catch (e) {
      return (
        fact: null,
        rejected: RejectedPacket(batchIndex: index, reason: 'corrupt: $e'),
      );
    }
  }

  /// Maps a validated ping to its canonical, provider-agnostic form.
  CanonicalFact _toCanonicalFact(
    RawTelemetryPing ping,
    RawTelemetryBatch batch,
  ) {
    return CanonicalFact.reconstitute(
      id: '',
      organizationId: batch.organizationId,
      rawPayloadId: '',
      deviceId: batch.deviceId,
      sourceAdapter: 'telemetry_normalizer',
      receivedAtUtc: _clock.nowUtc(),
      gpsTimestamp: ping.timestamp,
      lat: ping.latitude,
      lng: ping.longitude,
      integrityFlag: IngestionIntegrityFlag.ok,
    );
  }

  /// Stage 5 — INV-6/INV-18: groups facts by tenant|device and orders them by
  /// device-reported [CanonicalFact.gpsTimestamp].
  ///
  /// The sort is a pure reordering of existing UTC TIMESTAMPTZ values — it
  /// never reads a wall clock, so no clock drift is introduced.
  Map<String, List<CanonicalFact>> _organizeChronologically(
    List<CanonicalFact> facts,
  ) {
    final deviceBatches = <String, List<CanonicalFact>>{};
    for (final fact in facts) {
      final key = '${fact.organizationId}|${fact.deviceId}';
      (deviceBatches[key] ??= []).add(fact);
    }
    for (final batchFacts in deviceBatches.values) {
      batchFacts.sort((a, b) => a.gpsTimestamp.compareTo(b.gpsTimestamp));
    }
    return deviceBatches;
  }

  /// Stage 6 — INV-18: heuristic spoofing gate per device window.
  /// Writes the forensic record at the source before throwing.
  Future<void> _screenForSpoofing(
    Map<String, List<CanonicalFact>> deviceBatches,
    RawTelemetryBatch batch,
  ) async {
    for (final batchFacts in deviceBatches.values) {
      final risk = _spoofingDetector.analyze(batchFacts);
      if (!risk.isSuspected()) continue;

      const reason = 'spoofing detected by detector';
      await _recordSpoofingForensic(
        batch,
        deviceId: batch.deviceId,
        reason: reason,
        batchSize: batchFacts.length,
        riskScoreBps: risk.scoreBps,
      );
      throw SpoofingDetectedException(deviceId: batch.deviceId, reason: reason);
    }
  }

  /// Stage 7 — forensic auditability: one ledger entry per batch when packets
  /// were rejected. Never one entry per packet (INV-16 connection budget).
  Future<void> _recordRejections(
    NormalizationOutcome outcome,
    RawTelemetryBatch batch,
  ) async {
    if (outcome.rejectedCount == 0) return;

    final reasonCounts = <String, int>{};
    for (final packet in outcome.rejectedPackets) {
      reasonCounts[packet.reason] = (reasonCounts[packet.reason] ?? 0) + 1;
    }

    await ledgerRepository.append(
      SlaLedgerEntry(
        organizationId: batch.organizationId,
        type: 'TELEMETRY_PARTIAL_REJECT',
        contractId: 'TELEMETRY_INGESTION',
        planVersion: 1,
        occurredAtUtc: _clock.nowUtc(),
        payload: {
          'callerUserId': batch.callerUserId,
          'deviceId': batch.deviceId,
          'acceptedCount': outcome.acceptedCount,
          'rejectedCount': outcome.rejectedCount,
          'rejectionReasons': reasonCounts,
        },
      ),
    );
  }

  /// Stage 8 — dispatches accepted facts to the Engine queue.
  void _dispatchToEngine(List<CanonicalFact> facts) {
    for (final fact in facts) {
      factQueue.enqueue(fact);
    }
  }

  /// Shared forensic writer for both spoofing gates — single source of the
  /// `SPOOFING_DETECTED` ledger entry, guaranteeing exactly one write per
  /// quarantined batch.
  Future<void> _recordSpoofingForensic(
    RawTelemetryBatch batch, {
    required String deviceId,
    required String reason,
    required int batchSize,
    int? riskScoreBps,
  }) async {
    await ledgerRepository.append(
      SlaLedgerEntry(
        organizationId: batch.organizationId,
        type: 'SPOOFING_DETECTED',
        contractId: 'FRAUD_DETECTION',
        planVersion: 1,
        occurredAtUtc: _clock.nowUtc(),
        payload: {
          'callerUserId': batch.callerUserId,
          'deviceId': deviceId,
          'reason': reason,
          'batchSize': batchSize,
          'riskScoreBps': ?riskScoreBps,
        },
      ),
    );
  }
}

abstract class FactQueue {
  void enqueue(CanonicalFact fact);
}

abstract class SlaLedgerRepository {
  Future<String> append(SlaLedgerEntry entry);
}
