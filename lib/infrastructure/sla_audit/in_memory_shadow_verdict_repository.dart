import '../../domain/sla_audit/shadow_verdict.dart';
import '../../domain/sla_audit/shadow_verdict_repository.dart';

/// In-memory implementation of [ShadowVerdictRepository] for unit testing.
///
/// [syncManualVerdicts] does nothing by default. Use [addManualDecision] in
/// test setup to pre-register human decisions that [syncManualVerdicts] will
/// apply to matching pending shadow verdicts.
class InMemoryShadowVerdictRepository implements ShadowVerdictRepository {
  final List<ShadowVerdict> _verdicts = [];

  // keyed on 'setId::contractId' → manual decision data
  final Map<String, _ManualDecision> _pendingDecisions = {};

  @override
  Future<void> save(ShadowVerdict verdict) async {
    final key = _key(verdict.setId, verdict.contractId);
    final exists = _verdicts.any(
      (v) =>
          v.organizationId == verdict.organizationId &&
          _key(v.setId, v.contractId) == key,
    );
    if (!exists) _verdicts.add(verdict);
  }

  @override
  Future<List<ShadowVerdict>> findByOrganization({
    required String organizationId,
    required DateTime fromUtc,
    required DateTime toUtc,
    int limit = 100,
  }) async {
    return _verdicts
        .where(
          (v) =>
              v.organizationId == organizationId &&
              !v.createdAtUtc.isBefore(fromUtc) &&
              !v.createdAtUtc.isAfter(toUtc),
        )
        .toList()
      ..sort((a, b) => b.createdAtUtc.compareTo(a.createdAtUtc));
  }

  @override
  Future<List<ShadowVerdict>> findDivergent({
    required String organizationId,
    required DateTime fromUtc,
    required DateTime toUtc,
  }) async {
    return _verdicts
        .where(
          (v) =>
              v.organizationId == organizationId &&
              !v.createdAtUtc.isBefore(fromUtc) &&
              !v.createdAtUtc.isAfter(toUtc) &&
              (v.divergenceType == ShadowDivergenceType.falsePositive ||
                  v.divergenceType == ShadowDivergenceType.falseNegative),
        )
        .toList()
      ..sort((a, b) => b.createdAtUtc.compareTo(a.createdAtUtc));
  }

  @override
  Future<int> syncManualVerdicts({required String organizationId}) async {
    if (_pendingDecisions.isEmpty) return 0;
    var count = 0;
    for (var i = 0; i < _verdicts.length; i++) {
      final sv = _verdicts[i];
      if (sv.organizationId != organizationId) continue;
      if (sv.divergenceType != ShadowDivergenceType.pendingManual) continue;

      final decision = _pendingDecisions[_key(sv.setId, sv.contractId)];
      if (decision == null) continue;

      _verdicts[i] = sv.withManualVerdict(
        manualVerdict: decision.verdict,
        manualVerdictAtUtc: decision.reviewedAtUtc,
        manualReviewedBy: decision.reviewedBy,
      );
      count++;
    }
    return count;
  }

  // ── Test helpers ───────────────────────────────────────────────────────────

  /// Pre-registers a human decision for [syncManualVerdicts] to apply.
  void addManualDecision({
    required String setId,
    required String contractId,
    required String verdict,
    required DateTime reviewedAtUtc,
    required String reviewedBy,
  }) {
    _pendingDecisions[_key(setId, contractId)] = _ManualDecision(
      verdict: verdict,
      reviewedAtUtc: reviewedAtUtc,
      reviewedBy: reviewedBy,
    );
  }

  List<ShadowVerdict> get all => List.unmodifiable(_verdicts);
  int get count => _verdicts.length;
  void clear() {
    _verdicts.clear();
    _pendingDecisions.clear();
  }

  static String _key(String setId, String contractId) =>
      '$setId::$contractId';
}

class _ManualDecision {
  final String verdict;
  final DateTime reviewedAtUtc;
  final String reviewedBy;

  const _ManualDecision({
    required this.verdict,
    required this.reviewedAtUtc,
    required this.reviewedBy,
  });
}
