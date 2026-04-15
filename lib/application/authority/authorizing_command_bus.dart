import 'package:uuid/uuid.dart';
import 'package:veraprob/application/operational_control_service.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/authority/commands/contracts/update_contract_command.dart';
import 'package:veraprob/domain/authority/commands/trips/resolve_alert_command.dart';
import 'package:veraprob/domain/authority/commands/trips/create_trip_event_command.dart';
import 'package:veraprob/domain/authority/core/operational_action_mapper.dart';
import 'package:veraprob/domain/authority/decision/authorization_decision.dart';
import 'package:veraprob/domain/authority/policies/authority_policy_evaluator.dart';
import 'package:veraprob/domain/authority/repositories/forensic_decision_repository.dart';
import 'operational_command_bus.dart';

/// Concrete and purely synchronous Interceptor that orchestrates the Trust phase.
///
/// Refined for RED TEAM requirements:
/// 1. Tenant Isolation (Immediate Cross-Tenant Veto)
/// 2. Role Validation (via PolicyEvaluator)
/// 3. Forensic UTC Transparency (INV-9)
class AuthorizingCommandBus implements OperationalCommandBus {
  final AuthorityPolicyEvaluator _policyEvaluator;
  final ForensicDecisionRepository _decisionRepository;

  /// A session provider function (mocking real auth state for Phase 4)
  final AuthorizationContext Function() _sessionContextProvider;

  /// The actual Mutator service
  final OperationalControlService _controlService;

  final IDateTimeProvider _dateTimeProvider;

  AuthorizingCommandBus(
    this._policyEvaluator,
    this._decisionRepository,
    this._sessionContextProvider,
    this._controlService,
    this._dateTimeProvider,
  );

  @override
  Future<void> dispatch(OperationalCommand command) async {
    // 1. Identify intent semantically
    final actionType = OperationalActionMapper.inferActionType(command);

    // 2. Build live context snapshot (Injected from Auth Session)
    final context = _sessionContextProvider();

    // 3. SECURITY GATE: Cross-Tenant Isolation (Immediate Veto)
    // If the command specifies a target organization and it doesn't match the user's tenant,
    // we veto immediately without even touching the policy evaluator.
    if (command.targetOrganizationId != null &&
        command.targetOrganizationId != context.tenantId) {
      final vetoDecision = AuthorizationDecision(
        decisionId: const Uuid().v4(),
        actorId: context.actorId,
        roleId: context.roleId,
        actionType: actionType,
        targetRef: command.targetRef,
        policyVersion: 'system:isolation:v1',
        result: DecisionResult.denied,
        reason:
            'CROSS-TENANT VETO: User ${context.tenantId} attempted action on ${command.targetOrganizationId}',
        occurredAt: _dateTimeProvider.nowUtc(),
        contextSnapshot: context.toJson(),
      );

      await _decisionRepository.saveDecision(vetoDecision);

      throw UnauthorizedActionException(
        'Access Denied: Tenant Mismatch detected for $actionType',
      );
    }

    // 4. Evaluate Policy (Domain rules like Driver vs Admin)
    final decision = await _policyEvaluator.evaluate(
      actionType: actionType,
      context: context,
      targetRef: command.targetRef,
      nowUtc: _dateTimeProvider.nowUtc(),
    );

    // 5. Forensically Persist BEFORE execution (Ensures auditability)
    await _decisionRepository.saveDecision(decision);

    // 6. Block or Proceed
    if (!decision.isApproved) {
      throw UnauthorizedActionException(
        decision.reason ?? 'Policy denied action $actionType',
      );
    }

    // 7. Execute Mutation safely behind the Trust Barrier
    if (command is ResolveAlertCommand) {
      await _controlService.resolveAlert(command.tripId);
    } else if (command is CreateTripEventCommand) {
      await _controlService.createTripEvent(
        command.tripId,
        command.type,
        metadata: command.metadata,
        notes: command.notes,
      );
    } else if (command is UpdateContractCommand) {
      await _controlService.updateContract(
        command.contractId,
        command.newValueCents,
      );
    }
  }
}
