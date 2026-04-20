import 'package:veraprob/domain/authority/commands/contracts/update_contract_command.dart';
import 'authority_types.dart';
import 'package:veraprob/domain/authority/commands/operational_command.dart';
import 'package:veraprob/domain/authority/commands/trips/resolve_alert_command.dart';
import 'package:veraprob/domain/authority/commands/trips/update_trip_status_command.dart';
import 'package:veraprob/domain/authority/commands/trips/override_route_deviation_command.dart';
import 'package:veraprob/domain/authority/commands/trips/acknowledge_alert_command.dart';
import 'package:veraprob/domain/authority/commands/trips/create_trip_event_command.dart';
import 'package:veraprob/domain/authority/commands/vehicles/reassign_vehicle_command.dart';

/// Centralized router linking concrete Command intentions to Abstract ActionTypes.
///
/// This guarantees that Policy Rules evaluate against stable ActionTypes
/// (`action_resolve_alert`) instead of coupling to Dart classes
/// (`ResolveAlertCommand`).
class OperationalActionMapper {
  OperationalActionMapper._(); // Static utility

  /// Resolves the intended [OperationalActionType] for a given [OperationalCommand].
  static OperationalActionType inferActionType(OperationalCommand command) {
    if (command is ResolveAlertCommand) {
      return OperationalActionType.resolveAlert;
    }

    if (command is UpdateTripStatusCommand) {
      return OperationalActionType.overrideTripStatus;
    }

    if (command is AcknowledgeAlertCommand) {
      return OperationalActionType.acknowledgeAlert;
    }

    if (command is ReassignVehicleCommand) {
      return OperationalActionType.reassignVehicle;
    }

    if (command is CreateTripEventCommand) {
      return OperationalActionType.createTripEvent;
    }

    if (command is OverrideRouteDeviationCommand) {
      return OperationalActionType.overrideRouteDeviation;
    }

    if (command is UpdateContractCommand) {
      return OperationalActionType.updateContract;
    }

    // Fallback or explicit Unknown. In production we might throw Exception
    // to strictly enforce mapping of all commands to a granular ActionType.
    throw UnimplementedError(
      'Missing OperationalActionType mapping for Command type: ${command.runtimeType}',
    );
  }
}
