import 'package:flutter/foundation.dart';

import 'package:veraprob/domain/authority/commands/trips/resolve_alert_command.dart';
import 'package:veraprob/domain/authority/commands/trips/create_trip_event_command.dart';
import 'package:veraprob/domain/enums/event_type.dart';
import 'package:veraprob/domain/auth/i_auth_repository.dart';

export '../../domain/enums/event_type.dart';
import 'package:veraprob/application/authority/operational_command_bus.dart';

/// Application Facade for Operational Intent.
///
/// INV-1 Compliance: Injects [IAuthRepository] to obtain real
/// organization_id and role from authenticated session.
/// The UI (Widgets, Controllers) must NEVER know that a CommandBus exists.
class OperationalControlFacade {
  final OperationalCommandBus _commandBus;
  final IAuthRepository _authRepo;

  OperationalControlFacade(this._commandBus, this._authRepo);

  /// Called by the UI when a user clicks "Resolve Alert".
  ///
  /// INV-1: Obtains organization_id and role from authenticated session.
  Future<void> resolveAlert({required String tripId}) async {
    final user = await _authRepo.getCurrentUser();
    if (user == null) {
      throw const UnauthorizedActionException('No authenticated session');
    }

    final command = ResolveAlertCommand(tripId: tripId);

    try {
      if (kDebugMode) {
        print('====== UI DISPATCHING: Resolve Alert on $tripId ======');
      }

      await _commandBus.dispatch(command);

      if (kDebugMode) {
        print('====== UI RECEIVED: Success! Update Screen. ======');
      }
    } on UnauthorizedActionException catch (e) {
      if (kDebugMode) {
        print('====== UI RECEIVED: ERROR! Policy Blocked. ======');
        print('Reason: ${e.reason}');
      }
      rethrow;
    }
  }

  /// Called by the UI when a user registers a new occurrence (Trip Event).
  Future<void> createTripEvent({
    required String tripId,
    required EventType type,
    Map<String, dynamic>? metadata,
    String? notes,
  }) async {
    final user = await _authRepo.getCurrentUser();
    if (user == null) {
      throw const UnauthorizedActionException('No authenticated session');
    }

    final command = CreateTripEventCommand(
      tripId: tripId,
      type: type,
      metadata: metadata,
      notes: notes,
    );

    try {
      if (kDebugMode) {
        print('====== UI DISPATCHING: Create Trip Event on $tripId ======');
      }

      await _commandBus.dispatch(command);

      if (kDebugMode) {
        print('====== UI RECEIVED: Success! Update Screen. ======');
      }
    } on UnauthorizedActionException catch (e) {
      if (kDebugMode) {
        print('====== UI RECEIVED: ERROR! Policy Blocked. ======');
        print('Reason: ${e.reason}');
      }
      rethrow;
    }
  }
}
