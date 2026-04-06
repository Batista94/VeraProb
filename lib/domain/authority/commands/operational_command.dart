import 'package:equatable/equatable.dart';
import 'package:veraprob/domain/authority/core/authority_types.dart';

/// Base interface for all Intent Mails (Commands) targeting the Operational Core.
///
/// A Command must be a pure, immutable Data Transfer Object (DTO).
/// It contains ZERO business logic, ZERO policy awareness, and ZERO validation.
/// It exists solely to encapsulate the information required to perform an action.
abstract class OperationalCommand extends Equatable {
  const OperationalCommand();

  /// Identifies the semantic target of this command.
  ///
  /// This allows the Interceptor and Forensic Backbone to generically snapshot
  /// what entity is being mutated without needing reflection or hardcoded switch-cases.
  TargetRef get targetRef;
}
