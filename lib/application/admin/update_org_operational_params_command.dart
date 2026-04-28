import 'package:veraprob/domain/enums/user_role.dart';

/// Command for updating operational parameters by org admin (Stage G).
///
/// Admin de org pode editar dwell_time_seconds e max_kinematic_speed_kmh.
/// SuperAdmin define apenas valores iniciais no setup.
class UpdateOrgOperationalParamsCommand {
  final String organizationId;
  final UserRole callerRole;
  final int? dwellTimeSeconds;
  final double? maxKinematicSpeedKmh; // Physical Metric - Double Required
  final String reason;
  final String sessionId;

  const UpdateOrgOperationalParamsCommand({
    required this.organizationId,
    required this.callerRole,
    this.dwellTimeSeconds,
    this.maxKinematicSpeedKmh,
    required this.reason,
    required this.sessionId,
  });
}
