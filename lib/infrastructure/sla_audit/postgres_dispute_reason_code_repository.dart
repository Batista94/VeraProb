import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:veraprob/domain/sla_audit/dispute_reason_code.dart';
import 'package:veraprob/domain/sla_audit/dispute_reason_code_repository.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Postgres implementation of [DisputeReasonCodeRepository].
///
/// Read-only against the global `dispute_reason_codes` catalogue. Tenant scope
/// is enforced by RLS (`drc_select_global`): the row set is global codes
/// (`organization_id IS NULL`) plus any code owned by the caller's org. The
/// [organizationId] argument is accepted for forward-compatibility with the
/// future custom-codes phase but is NOT used to filter here — RLS already does.
class PostgresDisputeReasonCodeRepository extends BasePostgresRepository
    implements DisputeReasonCodeRepository {
  PostgresDisputeReasonCodeRepository(super.client);

  @override
  Future<List<DisputeReasonCode>> findAllActive({String? organizationId}) {
    return withErrorHandler('dispute_reason_code', null, () async {
      final rows = await client
          .from('dispute_reason_codes')
          .select('code, category, label_pt, label_en, is_active, applies_to')
          .eq('is_active', true)
          .order('category')
          .order('code');
      return rows.map((r) => mapRow(r)).toList(growable: false);
    });
  }

  static DisputeReasonContext _mapContext(String? val) {
    switch (val) {
      case 'REJECTION':
        return DisputeReasonContext.rejection;
      case 'RESOLUTION':
        return DisputeReasonContext.resolution;
      default:
        return DisputeReasonContext.all;
    }
  }

  @visibleForTesting
  static DisputeReasonCode mapRow(Map<String, dynamic> row) =>
      DisputeReasonCode(
        code: row['code'] as String,
        category: row['category'] as String,
        labelPt: row['label_pt'] as String,
        labelEn: row['label_en'] as String,
        isActive: row['is_active'] as bool,
        appliesTo: _mapContext(row['applies_to'] as String?),
      );
}
