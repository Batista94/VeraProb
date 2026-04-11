import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/core/config/supabase_client.dart';
import 'package:veraprob/domain/sla_audit/shadow_verdict.dart';
import 'package:veraprob/domain/sla_audit/shadow_verdict_repository.dart';
import 'package:veraprob/infrastructure/shared/postgres_error_interceptor.dart';

/// Postgres implementation of [ShadowVerdictRepository].
///
/// **Architecture Guarantees:**
/// 1. **Idempotent save**: UPSERT with `ON CONFLICT (organization_id, set_id, contract_id)
///    DO NOTHING` — a second engine run for the same obligation is a no-op (INV-11).
/// 2. **Tenant isolation**: All queries scoped to `organization_id` (INV-1).
/// 3. **Immutability**: DB trigger `trg_shadow_verdicts_immutable` blocks UPDATE of
///    engine fields. Only [syncManualVerdicts] updates manual/divergence columns (INV-7).
/// 4. **No delete**: No delete method exists on this class (INV-7).
/// 5. **Explicit columns**: No `select('*')` — column lists are declared in [_columns].
class PostgresShadowVerdictRepository
    with PostgresErrorInterceptor
    implements ShadowVerdictRepository {
  final SupabaseClient _client;

  PostgresShadowVerdictRepository([SupabaseClient? client])
    : _client = client ?? supabase;

  // ── Column projection (security rule: no select('*')) ─────────────────────
  static const _columns =
      'id, organization_id, set_id, contract_id, '
      'engine_verdict, engine_verdict_at_utc, engine_version, '
      'verdict_evidence, traceability_hash, divergence_type, '
      'manual_verdict, manual_verdict_at_utc, manual_reviewed_by, created_at';

  static const _srqColumns =
      'set_id, contract_id, status, reviewed_at, reviewed_by';

  // ── Write ──────────────────────────────────────────────────────────────────

  @override
  Future<void> save(ShadowVerdict verdict) async {
    try {
      await _client
          .from('shadow_verdicts')
          .upsert(
            {
              'id': verdict.id,
              'organization_id': verdict.organizationId,
              'set_id': verdict.setId,
              'contract_id': verdict.contractId,
              'engine_verdict': verdict.engineVerdict,
              'engine_verdict_at_utc': verdict.engineVerdictAtUtc
                  .toIso8601String(),
              'engine_version': verdict.engineVersion,
              'verdict_evidence': verdict.verdictEvidence.toJson(),
              'traceability_hash': verdict.traceabilityHash,
              'divergence_type': _divergenceToString(verdict.divergenceType),
              'created_at': verdict.createdAtUtc.toIso8601String(),
            },
            // UPSERT: second call for the same obligation is silently ignored (INV-11).
            onConflict: 'organization_id,set_id,contract_id',
            ignoreDuplicates: true,
          );
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'shadow_verdict');
    }
  }

  // ── Read ───────────────────────────────────────────────────────────────────

  @override
  Future<List<ShadowVerdict>> findByOrganization({
    required String organizationId,
    required DateTime fromUtc,
    required DateTime toUtc,
    int limit = 100,
  }) async {
    try {
      final rows = await _client
          .from('shadow_verdicts')
          .select(_columns)
          .eq('organization_id', organizationId)
          .gte('created_at', fromUtc.toIso8601String())
          .lte('created_at', toUtc.toIso8601String())
          .order('created_at', ascending: false)
          .limit(limit);

      return (rows as List)
          .map((r) => _fromRow(r as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'shadow_verdict');
    }
  }

  @override
  Future<List<ShadowVerdict>> findDivergent({
    required String organizationId,
    required DateTime fromUtc,
    required DateTime toUtc,
  }) async {
    try {
      final rows = await _client
          .from('shadow_verdicts')
          .select(_columns)
          .eq('organization_id', organizationId)
          .inFilter('divergence_type', ['false_positive', 'false_negative'])
          .gte('created_at', fromUtc.toIso8601String())
          .lte('created_at', toUtc.toIso8601String())
          .order('created_at', ascending: false)
          .limit(500);

      return (rows as List)
          .map((r) => _fromRow(r as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'shadow_verdict');
    }
  }

  // ── Sync ───────────────────────────────────────────────────────────────────

  @override
  Future<int> syncManualVerdicts({required String organizationId}) async {
    // Step 1: fetch shadow verdicts still awaiting a human decision.
    final dynamic pendingRows;
    try {
      pendingRows = await _client
          .from('shadow_verdicts')
          .select(_columns)
          .eq('organization_id', organizationId)
          .isFilter('manual_verdict', null)
          .limit(500);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'shadow_verdict');
    }

    if (pendingRows is! List) return 0;
    final pending = pendingRows
        .map((r) => _fromRow(r as Map<String, dynamic>))
        .toList();

    if (pending.isEmpty) return 0;

    // Step 2: fetch reviewed sanction queue entries for the same org.
    final dynamic srqRows;
    try {
      srqRows = await _client
          .from('sanction_review_queue')
          .select(_srqColumns)
          .eq('organization_id', organizationId)
          .inFilter('status', ['applied', 'rejected'])
          .limit(1000);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'shadow_verdict');
    }

    if (srqRows is! List || srqRows.isEmpty) return 0;

    // Step 3: build a lookup keyed on (set_id, contract_id).
    final srqByKey = <String, Map<String, dynamic>>{};
    for (final row in srqRows) {
      final map = row as Map<String, dynamic>;
      final key = '${map['set_id']}::${map['contract_id']}';
      srqByKey[key] = map;
    }

    // Step 4: match pending shadow verdicts to reviewed SRQ entries,
    // compute divergence, and persist.
    var updated = 0;
    for (final sv in pending) {
      final key = '${sv.setId}::${sv.contractId}';
      final srq = srqByKey[key];
      if (srq == null) continue;

      final manualVerdict = srq['status'] as String; // 'applied' | 'rejected'
      final reviewedAt = srq['reviewed_at'] as String?;
      final reviewedBy = srq['reviewed_by'] as String?;

      if (reviewedAt == null || reviewedBy == null) continue;

      final classified = sv.withManualVerdict(
        manualVerdict: manualVerdict,
        manualVerdictAtUtc: DateTime.parse(reviewedAt),
        manualReviewedBy: reviewedBy,
      );

      try {
        await _client
            .from('shadow_verdicts')
            .update({
              'manual_verdict': classified.manualVerdict,
              'manual_verdict_at_utc': classified.manualVerdictAtUtc
                  ?.toIso8601String(),
              'manual_reviewed_by': classified.manualReviewedBy,
              'divergence_type': _divergenceToString(classified.divergenceType),
            })
            .eq('id', classified.id)
            .eq('organization_id', classified.organizationId);
      } on PostgrestException catch (e) {
        throw mapPostgrestToDomainException(e, resourceType: 'shadow_verdict');
      }

      updated++;
    }

    return updated;
  }

  // ── Mapping helpers ────────────────────────────────────────────────────────

  static ShadowVerdict _fromRow(Map<String, dynamic> row) {
    return ShadowVerdict.fromJson({
      'id': row['id'],
      'organization_id': row['organization_id'],
      'set_id': row['set_id'],
      'contract_id': row['contract_id'],
      'engine_verdict': row['engine_verdict'],
      'engine_verdict_at_utc': row['engine_verdict_at_utc'],
      'engine_version': row['engine_version'],
      'verdict_evidence': row['verdict_evidence'],
      'traceability_hash': row['traceability_hash'],
      'divergence_type': row['divergence_type'],
      'manual_verdict': row['manual_verdict'],
      'manual_verdict_at_utc': row['manual_verdict_at_utc'],
      'manual_reviewed_by': row['manual_reviewed_by'],
      'created_at': row['created_at'],
    });
  }

  static String _divergenceToString(ShadowDivergenceType type) =>
      switch (type) {
        ShadowDivergenceType.match => 'match',
        ShadowDivergenceType.falsePositive => 'false_positive',
        ShadowDivergenceType.falseNegative => 'false_negative',
        ShadowDivergenceType.pendingManual => 'pending_manual',
      };
}
