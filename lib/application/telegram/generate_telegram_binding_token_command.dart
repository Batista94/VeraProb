import 'package:veraprob/domain/enums/user_role.dart';

/// Command to generate a 15-minute binding code for a specific driver.
class GenerateTelegramBindingTokenCommand {
  final String organizationId;
  final String driverId;
  final UserRole callerRole;
  final String callerUserId;
  final String sessionId;

  const GenerateTelegramBindingTokenCommand({
    required this.organizationId,
    required this.driverId,
    required this.callerRole,
    required this.callerUserId,
    required this.sessionId,
  });
}
