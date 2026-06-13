// pr_scanner: ignore-regression
// Council-reviewed (Phase 10.6 v3 council-remediated plan, 2026-06-12):
// dispute reality core — evidence/reason-code/command contracts (INV-1/3/9).
import 'package:veraprob/domain/sla_audit/dispute_reason_code.dart';

/// Port for the reason code catalogue (read-only in v1).
abstract class DisputeReasonCodeRepository {
  /// All active codes. [organizationId] is accepted now (forward-compatible with
  /// the future custom-codes phase) though v1 returns only global codes.
  Future<List<DisputeReasonCode>> findAllActive({String? organizationId});
}
