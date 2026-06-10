import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/sanction_transition_guard.dart';

void main() {
  const guard = SanctionTransitionGuard();

  group('SanctionTransitionGuard - legal arcs', () {
    final legal = <(SanctionReviewStatus, SanctionReviewStatus)>[
      (SanctionReviewStatus.pending, SanctionReviewStatus.applied),
      (SanctionReviewStatus.pending, SanctionReviewStatus.rejected),
      (SanctionReviewStatus.pending, SanctionReviewStatus.disputed),
      (SanctionReviewStatus.disputed, SanctionReviewStatus.applied),
      (SanctionReviewStatus.disputed, SanctionReviewStatus.rejected),
      (SanctionReviewStatus.disputed, SanctionReviewStatus.pending),
      // Dual-control fork + resolution (Phase 10.5 Item 2).
      (SanctionReviewStatus.pending, SanctionReviewStatus.pendingPeerReview),
      (SanctionReviewStatus.disputed, SanctionReviewStatus.pendingPeerReview),
      (SanctionReviewStatus.pendingPeerReview, SanctionReviewStatus.applied),
      (SanctionReviewStatus.pendingPeerReview, SanctionReviewStatus.rejected),
      (SanctionReviewStatus.pendingPeerReview, SanctionReviewStatus.pending),
      (SanctionReviewStatus.pendingPeerReview, SanctionReviewStatus.disputed),
    ];

    for (final (from, to) in legal) {
      test('allows ${from.name} -> ${to.name}', () {
        expect(() => guard.assertTransitionAllowed(from, to), returnsNormally);
      });
    }
  });

  group('SanctionTransitionGuard - illegal arcs', () {
    final illegal = <(SanctionReviewStatus, SanctionReviewStatus)>[
      // Terminal states have no outgoing arcs.
      (SanctionReviewStatus.applied, SanctionReviewStatus.pending),
      (SanctionReviewStatus.applied, SanctionReviewStatus.rejected),
      (SanctionReviewStatus.applied, SanctionReviewStatus.disputed),
      (SanctionReviewStatus.applied, SanctionReviewStatus.applied),
      (SanctionReviewStatus.rejected, SanctionReviewStatus.pending),
      (SanctionReviewStatus.rejected, SanctionReviewStatus.applied),
      (SanctionReviewStatus.rejected, SanctionReviewStatus.disputed),
      (SanctionReviewStatus.rejected, SanctionReviewStatus.rejected),
      // No self-loops on transient states.
      (SanctionReviewStatus.pending, SanctionReviewStatus.pending),
      (SanctionReviewStatus.disputed, SanctionReviewStatus.disputed),
      (
        SanctionReviewStatus.pendingPeerReview,
        SanctionReviewStatus.pendingPeerReview,
      ),
      // Terminal states never enter peer review.
      (SanctionReviewStatus.applied, SanctionReviewStatus.pendingPeerReview),
      (SanctionReviewStatus.rejected, SanctionReviewStatus.pendingPeerReview),
    ];

    for (final (from, to) in illegal) {
      test('rejects ${from.name} -> ${to.name}', () {
        expect(
          () => guard.assertTransitionAllowed(from, to),
          throwsA(isA<DomainException>()),
        );
      });
    }

    test('exception message names the illegal transition', () {
      expect(
        () => guard.assertTransitionAllowed(
          SanctionReviewStatus.applied,
          SanctionReviewStatus.disputed,
        ),
        throwsA(
          isA<DomainException>().having(
            (e) => e.message,
            'message',
            allOf(contains('applied'), contains('disputed')),
          ),
        ),
      );
    });
  });
}
