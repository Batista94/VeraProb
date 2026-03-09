import 'dart:async';
import '../decision/authorization_decision.dart';
import 'forensic_decision_repository.dart';

/// In-Memory Stub for Phase 3 Forensic Append-Only DB.
class InMemoryForensicRepository implements ForensicDecisionRepository {
  final List<AuthorizationDecision> _ledger = [];
  final _controller = StreamController<List<AuthorizationDecision>>.broadcast();

  List<AuthorizationDecision> get testLedgerArray => List.unmodifiable(_ledger);

  InMemoryForensicRepository() {
    // Emit initial empty state on the next microtask so subscribers
    // registered synchronously after construction receive it.
    scheduleMicrotask(() {
      if (!_controller.isClosed) {
        _controller.add(List.unmodifiable(_ledger));
      }
    });
  }

  @override
  Future<void> saveDecision(AuthorizationDecision decision) async {
    _ledger.add(decision);
    if (!_controller.isClosed) {
      _controller.add(List.unmodifiable(_ledger));
    }

    assert(() {
      final mark = decision.isApproved ? 'APPROVED' : 'DENIED';
      // ignore: avoid_print
      print(
        '[FORENSIC LEDGER] $mark | Action: ${decision.actionType.key} | Actor: ${decision.actorId.value} | Target: ${decision.targetRef.urn}',
      );
      return true;
    }());
  }

  // Stream for projections
  Stream<List<AuthorizationDecision>> get ledgerStream => _controller.stream;

  // Developer inspection only
  int get ledgerCount => _ledger.length;

  void dispose() {
    _controller.close();
  }
}
