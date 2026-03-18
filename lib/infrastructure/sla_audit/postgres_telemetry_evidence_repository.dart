import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_client.dart';
import '../../domain/sla_audit/telemetry_evidence.dart';
import '../../domain/sla_audit/telemetry_evidence_repository.dart';

/// Postgres implementation of [TelemetryEvidenceRepository].
///
/// Append-only (INV-1): only INSERT is used. No UPDATE or DELETE.
/// The DB-level UNIQUE constraint on `content_hash` enforces duplicate
/// detection. The `chain_hash` column is GENERATED ALWAYS AS in Postgres
/// (pgcrypto), so it is NOT sent in the INSERT payload.
///
/// **Prerequisite:** SQL Block C from Sprint 5.13 Bloco 6.2 must be applied
/// before this repository can be used against a live Supabase project.
class PostgresTelemetryEvidenceRepository
    implements TelemetryEvidenceRepository {
  final SupabaseClient _client;

  PostgresTelemetryEvidenceRepository([SupabaseClient? client])
    : _client = client ?? supabase;

  @override
  Future<void> save(TelemetryEvidence evidence) async {
    await _client.from('telemetry_evidences').insert({
      'id': evidence.id,
      'organization_id': evidence.organizationId,
      'set_id': evidence.setId,
      'vehicle_id': evidence.vehicleId,
      'captured_at_utc': evidence.capturedAtUtc.toIso8601String(),
      'raw_latitude': evidence.rawLatitude,
      'raw_longitude': evidence.rawLongitude,
      'raw_speed_cms': evidence.rawSpeedCms,
      'source_type': evidence.sourceType,
      'content_hash': evidence.contentHash,
      'previous_evidence_hash': evidence.previousEvidenceHash,
      // chain_hash is GENERATED ALWAYS AS in DB — not sent here.
    });
  }

  @override
  Future<List<TelemetryEvidence>> findBySetId(
    String setId, {
    required String organizationId,
  }) async {
    final List<dynamic> rows = await _client
        .from('telemetry_evidences')
        .select()
        .eq('organization_id', organizationId)
        .eq('set_id', setId)
        .order('seq', ascending: true);

    return rows.map((r) => _mapToEntity(r as Map<String, dynamic>)).toList();
  }

  @override
  Future<TelemetryEvidence?> findLatestBySetId(
    String setId, {
    required String organizationId,
  }) async {
    final row = await _client
        .from('telemetry_evidences')
        .select()
        .eq('organization_id', organizationId)
        .eq('set_id', setId)
        .order('seq', ascending: false)
        .limit(1)
        .maybeSingle();

    if (row == null) return null;
    return _mapToEntity(row);
  }

  // ── Private mapper ─────────────────────────────────────────

  TelemetryEvidence _mapToEntity(Map<String, dynamic> row) {
    return TelemetryEvidence.reconstitute(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      setId: row['set_id'] as String,
      vehicleId: row['vehicle_id'] as String,
      capturedAtUtc: DateTime.parse(row['captured_at_utc'] as String).toUtc(),
      rawLatitude: (row['raw_latitude'] as num).toDouble(),
      rawLongitude: (row['raw_longitude'] as num).toDouble(),
      rawSpeedCms: row['raw_speed_cms'] as int?,
      sourceType: row['source_type'] as String,
      contentHash: row['content_hash'] as String,
      previousEvidenceHash: row['previous_evidence_hash'] as String,
      chainHash: row['chain_hash'] as String,
    );
  }
}
