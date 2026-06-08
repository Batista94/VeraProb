import 'domain_exception.dart';
import 'sanction_review_queue_entry.dart';

/// Centralized state-machine authority for [SanctionReviewStatus] transitions.
///
/// Pure domain service (no infrastructure dependencies). Every status change
/// — whether driven by approve/reject/dispute or by dispute resolution — must
/// be validated here so the legal arcs live in exactly one place (INV-15:
/// deterministic, auditable lifecycle).
///
/// Legal arcs:
/// - `pending`  → `applied` | `rejected` | `disputed`
/// - `disputed` → `applied` | `rejected` | `pending` (retract)
/// - `applied`, `rejected` are terminal (no outgoing arcs)
///
/// Note: this guard validates *state-machine legality*, not *handler
/// ownership*. The pending-only handlers (approve/reject/dispute) additionally
/// require a `pending` source so that the `disputed → *` arcs are owned
/// exclusively by the dispute-resolution flow.
class SanctionTransitionGuard {
  const SanctionTransitionGuard();

  static const Map<SanctionReviewStatus, Set<SanctionReviewStatus>> _allowed = {
    SanctionReviewStatus.pending: {
      SanctionReviewStatus.applied,
      SanctionReviewStatus.rejected,
      SanctionReviewStatus.disputed,
    },
    SanctionReviewStatus.disputed: {
      SanctionReviewStatus.applied,
      SanctionReviewStatus.rejected,
      SanctionReviewStatus.pending,
    },
    SanctionReviewStatus.applied: <SanctionReviewStatus>{},
    SanctionReviewStatus.rejected: <SanctionReviewStatus>{},
  };

  /// Throws [DomainException] (INV-10) naming the arc if [from] → [to] is not
  /// a legal sanction lifecycle transition.
  void assertTransitionAllowed(
    SanctionReviewStatus from,
    SanctionReviewStatus to,
  ) {
    final allowed = _allowed[from] ?? const <SanctionReviewStatus>{};
    if (!allowed.contains(to)) {
      throw DomainException(
        'Illegal sanction transition: ${from.name} -> ${to.name}.',
      );
    }
  }
}
