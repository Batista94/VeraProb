import 'package:veraprob/application/intelligence/telemetry_normalizer.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/entities/raw_telemetry_ping.dart';
import 'package:veraprob/domain/sla_audit/canonical_fact.dart';
import 'package:veraprob/domain/sla_audit/ingestion_integrity_flag.dart';
import 'package:veraprob/domain/sla_audit/spoofing_detector.dart';
import 'package:veraprob/domain/sla_audit/telemetry/spoofing_detected_exception.dart';
import 'package:veraprob/domain/sla_audit/telemetry/raw_telemetry_batch.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';

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

  Future<void> normalize(
    RawTelemetryBatch batch, {
    required String sessionId,
  }) async {
    // INV-1: Identity Sovereignty â€” fail-fast tenant check
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: batch.organizationId,
      sessionId: sessionId,
    );

    final pings = batch.coordinates
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

    try {
      normalizer.validateBatch(pings, batch.deviceId);

      final canonicalFacts = <CanonicalFact>[];
      for (final ping in pings) {
        final position = normalizer.processPing(ping);
        if (position != null) {
          canonicalFacts.add(
            CanonicalFact.reconstitute(
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
            ),
          );
        }
      }

      // Group by organizationId|deviceId and sort by occurredAt
      final deviceBatches = <String, List<CanonicalFact>>{};
      for (final fact in canonicalFacts) {
        final key = '${fact.organizationId}|${fact.deviceId}';
        (deviceBatches[key] ??= []).add(fact);
      }

      for (final entry in deviceBatches.entries) {
        final batchFacts = entry.value
          ..sort((a, b) => a.gpsTimestamp.compareTo(b.gpsTimestamp));

        final risk = _spoofingDetector.analyze(batchFacts);

        if (risk.isSuspected()) {
          await ledgerRepository.append(
            SlaLedgerEntry(
              organizationId: batch.organizationId,
              type: 'SPOOFING_DETECTED',
              contractId: 'FRAUD_DETECTION',
              planVersion: 1,
              occurredAtUtc: _clock.nowUtc(),
              payload: {
                'callerUserId': batch.callerUserId,
                'deviceId': batch.deviceId,
                'reason': 'spoofing detected by detector',
                'batchSize': batchFacts.length,
                'riskScoreBps': risk.scoreBps,
              },
            ),
          );
          throw SpoofingDetectedException(
            deviceId: batch.deviceId,
            reason: 'spoofing detected by detector',
          );
        }
      }

      for (final fact in canonicalFacts) {
        factQueue.enqueue(fact);
      }
    } on SpoofingDetectedException catch (e) {
      await ledgerRepository.append(
        SlaLedgerEntry(
          organizationId: batch.organizationId,
          type: 'SPOOFING_DETECTED',
          contractId: 'FRAUD_DETECTION',
          planVersion: 1,
          occurredAtUtc: _clock.nowUtc(),
          payload: {
            'callerUserId': batch.callerUserId,
            'deviceId': e.deviceId,
            'reason': e.reason,
            'batchSize': batch.coordinates.length,
          },
        ),
      );
      rethrow;
    }
  }
}

abstract class FactQueue {
  void enqueue(CanonicalFact fact);
}

abstract class SlaLedgerRepository {
  Future<String> append(SlaLedgerEntry entry);
}
