import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/sla_audit/spoofing_audit_entry.dart';
import '../../domain/sla_audit/spoofing_audit_repository.dart';
import '../../domain/sla_audit/spoofing_risk_score.dart';
import '../../domain/sla_audit/spoofing_signal.dart';

/// Postgres implementation of [SpoofingAuditRepository] using Supabase.
class PostgresSpoofingAuditRepository implements SpoofingAuditRepository {
  final SupabaseClient _client;

  PostgresSpoofingAuditRepository([SupabaseClient? client])
    : _client = client ?? Supabase.instance.client;

  @override
  Future<void> append(SpoofingAuditEntry entry) async {
    await _client.from('spoofing_audit_entries').insert({
      'id': entry.id,
      'organization_id': entry.organizationId,
      'device_id': entry.deviceId,
      'asset_id': entry.assetId,
      'window_start': entry.windowStart.toIso8601String(),
      'window_end': entry.windowEnd.toIso8601String(),
      'risk_score': entry.riskScore.score,
      'signals': entry.riskScore.signals.map((s) => s.name).toList(),
      'facts_analyzed': entry.factsAnalyzed,
      'fact_ids': entry.factIds,
      'content_hash': entry.contentHash,
      'created_at': entry.createdAt.toIso8601String(),
    });
  }

  @override
  Future<SpoofingAuditEntry?> getById(String id) async {
    final row = await _client
        .from('spoofing_audit_entries')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (row == null) return null;
    return _mapRowToEntry(row);
  }

  @override
  Future<List<SpoofingAuditEntry>> getPendingReview(String organizationId) async {
    final rows = await _client
        .from('spoofing_audit_entries')
        .select()
        .eq('organization_id', organizationId)
        .isFilter('reviewed_at', null)
        .order('window_end', ascending: false);

    return rows.map((row) => _mapRowToEntry(row)).toList();
  }

  @override
  Future<List<SpoofingAuditEntry>> getByDevice(
    String organizationId,
    String deviceId, {
    DateTime? from,
    DateTime? to,
  }) async {
    var query = _client
        .from('spoofing_audit_entries')
        .select()
        .eq('organization_id', organizationId)
        .eq('device_id', deviceId);

    if (from != null) query = query.gte('window_start', from.toIso8601String());
    if (to != null) query = query.lte('window_end', to.toIso8601String());

    final rows = await query.order('window_start', ascending: false);
    return rows.map((row) => _mapRowToEntry(row)).toList();
  }

  SpoofingAuditEntry _mapRowToEntry(Map<String, dynamic> row) {
    final signalsList = (row['signals'] as List<dynamic>?) ?? [];
    
    return SpoofingAuditEntry.reconstitute(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      deviceId: row['device_id'] as String,
      assetId: row['asset_id'] as String?,
      windowStart: DateTime.parse(row['window_start'] as String),
      windowEnd: DateTime.parse(row['window_end'] as String),
      riskScore: SpoofingRiskScore(
        score: (row['risk_score'] as num).toDouble(),
        signals: signalsList
            .map((s) => SpoofingSignal.values.firstWhere((e) => e.name == s))
            .toList(),
      ),
      factsAnalyzed: row['facts_analyzed'] as int,
      factIds: (row['fact_ids'] as List<dynamic>).map((id) => id as String).toList(),
      contentHash: row['content_hash'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      reviewedBy: row['reviewed_by'] as String?,
      reviewedAt: row['reviewed_at'] != null 
          ? DateTime.parse(row['reviewed_at'] as String) 
          : null,
      reviewOutcome: row['review_outcome'] as String?,
    );
  }
}
