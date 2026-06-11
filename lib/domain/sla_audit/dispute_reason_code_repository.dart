import 'package:veraprob/domain/sla_audit/dispute_reason_code.dart';

/// Port for the reason code catalogue (read-only in v1).
abstract class DisputeReasonCodeRepository {
  /// All active codes. [organizationId] is accepted now (forward-compatible with
  /// the future custom-codes phase) though v1 returns only global codes.
  Future<List<DisputeReasonCode>> findAllActive({String? organizationId});
}
