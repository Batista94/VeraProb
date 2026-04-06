import 'package:veraprob/domain/authority/commands/operational_command.dart';

export '../../domain/authority/commands/operational_command.dart';
export '../../domain/authority/commands/trips/update_trip_status_command.dart';

/// Application Port: The entry point for all Intentions.
///
/// The UI should NEVER call mutation services directly. Instead, it dispatches
/// an [OperationalCommand] here.
abstract class OperationalCommandBus {
  /// Dispatches a command synchronously for interception, validation, and execution.
  ///
  /// Throws an [UnauthorizedActionException] if the policy denies it.
  Future<void> dispatch(OperationalCommand command);
}

/// Thrown when the [AuthorityPolicyEvaluator] denies an Operational Action.
class UnauthorizedActionException implements Exception {
  final String reason;

  UnauthorizedActionException(this.reason);

  @override
  String toString() => 'UnauthorizedActionException: $reason';
}
