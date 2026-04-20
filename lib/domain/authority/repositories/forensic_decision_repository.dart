import 'package:veraprob/domain/authority/decision/authorization_decision.dart';

/// Domain Port: Immutable append-only storage for Forensic Decisions.
///
/// The backbone of enterprise responsibility. Once a decision is logged here,
/// it can never be altered or deleted.
abstract class ForensicDecisionRepository {
  /// Persists the decision permanently. Must be lightning fast (or buffered securely).
  Future<void> saveDecision(AuthorizationDecision decision);
}
