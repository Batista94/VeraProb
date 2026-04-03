import '../../../application/operational_control_service.dart';
import '../../domain/authority/commands/trips/resolve_alert_command.dart';
import '../../domain/authority/commands/trips/create_trip_event_command.dart';
import '../../domain/authority/core/operational_action_mapper.dart';
import '../../domain/authority/decision/authorization_decision.dart';
import '../../domain/authority/policies/authority_policy_evaluator.dart';
import '../../domain/authority/repositories/forensic_decision_repository.dart';
import 'operational_command_bus.dart';

/// Concrete and purely synchronous Interceptor that orchestrates the Trust phase.
///
/// 1. Maps Command -> ActionType
/// 2. Builds AuthorizationContext (Actor snapshot)
/// 3. Asks Evaluator for a Decision
/// 4. Persists the Decision securely (Forensic)
/// 5. EXECUTING MUTATION is intentionally omitted in this Stub phase.
///    It will delegate to `OperationalControlService` upon approval later.
class AuthorizingCommandBus implements OperationalCommandBus {
  final AuthorityPolicyEvaluator _policyEvaluator;
  final ForensicDecisionRepository _decisionRepository;

  /// A session provider function (mocking real auth state for Phase 4)
  final AuthorizationContext Function() _sessionContextProvider;

  /// The actual Mutator service
  final OperationalControlService _controlService;

  AuthorizingCommandBus(
    this._policyEvaluator,
    this._decisionRepository,
    this._sessionContextProvider,
    this._controlService,
  );

  @override
  Future<void> dispatch(OperationalCommand command) async {
    // 1. Identify intent semantically
    final actionType = OperationalActionMapper.inferActionType(command);

    // 2. Build live context snapshot (Injected from Auth Session)
    final context = _sessionContextProvider();

    // 3. Evaluate Policy (Domain rules)
    final decision = await _policyEvaluator.evaluate(
      actionType: actionType,
      context: context,
      targetRef: command.targetRef,
    );

    // 4. Forensically Persist BEFORE execution (Ensures auditability even if DB mutation fails later)
    await _decisionRepository.saveDecision(decision);

    // 5. Block or Proceed
    if (!decision.isApproved) {
      throw UnauthorizedActionException(
        decision.reason ?? 'Policy denied action $actionType',
      );
    }

    // 6. Execute Mutation safely behind the Trust Barrier
    if (command is ResolveAlertCommand) {
      await _controlService.resolveAlert(command.tripId);
    } else if (command is CreateTripEventCommand) {
      await _controlService.createTripEvent(
        command.tripId,
        command.type,
        metadata: command.metadata,
        notes: command.notes,
      );
    }
  }
}
