import 'package:veraprob/application/intelligence/telemetry_normalizer.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/entities/raw_telemetry_ping.dart';
import 'package:veraprob/domain/sla_audit/telemetry/canonical_fact.dart';
import 'package:veraprob/domain/sla_audit/telemetry/raw_telemetry_batch.dart';
import 'package:veraprob/domain/sla_audit/telemetry/spoofing_detected_exception.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';

class TelemetryNormalizationHandler {
  final TelemetryNormalizer normalizer;
  final SlaLedgerRepository ledgerRepository;
  final FactQueue factQueue;
  final IDateTimeProvider _clock;
  final TenantValidationService _tenantValidator;

  TelemetryNormalizationHandler({
    required this.normalizer,
    required this.ledgerRepository,
    required this.factQueue,
    required IDateTimeProvider clock,
    required TenantValidationService tenantValidator,
  }) : _clock = clock,
       _tenantValidator = tenantValidator;

  Future<void> normalize(RawTelemetryBatch batch) async {
    // INV-1: Identity Sovereignty — fail-fast tenant check
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: batch.organizationId,
      sessionId: '',
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

      for (final ping in pings) {
        final position = normalizer.processPing(ping);
        if (position != null) {
          factQueue.enqueue(
            CanonicalFact(
              deviceId: batch.deviceId,
              occurredAt: ping.timestamp,
              latitude: ping.latitude,
              longitude: ping.longitude,
              organizationId: batch.organizationId,
            ),
          );
        }
      }
    } on SpoofingDetectedException catch (e) {
      await ledgerRepository.append(
        SlaLedgerEntry(
          organizationId: batch.organizationId,
          type: 'SPOOFING_DETECTED',
          contractId: 'FRAUD_DETECTION',
          planVersion: 1,
          occurredAtUtc: _clock.now(),
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
