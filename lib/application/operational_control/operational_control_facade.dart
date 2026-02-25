import 'package:flutter/foundation.dart';

import '../../domain/authority/commands/trips/resolve_alert_command.dart';
import '../authority/operational_command_bus.dart';

/// Application Facade for Operational Intent.
///
/// The UI (Widgets, Controllers) must NEVER know that a CommandBus exists.
/// They call semantic methods on this Facade just like they would on any Service.
///
/// This class is responsible for:
/// 1. Instantiating the concrete [OperationalCommand] DTOs.
/// 2. (In Phase 3/4) Providing the Mock [AuthorizationContext] to the Bus (eventually this comes from Auth layer).
/// 3. Hiding complex Domain/Authority exceptions behind UI-friendly error states if needed.
class OperationalControlFacade {
  final OperationalCommandBus _commandBus;

  OperationalControlFacade(this._commandBus);

  /// Called by the UI when a user clicks "Resolve Alert".
  ///
  /// In this Phase 4 Stub, we accept a [simulateRole] to test the Interceptor
  /// rules without having real authentication wired up yet.
  Future<void> resolveAlert({
    required String tripId,
    required String simulateRole, // e.g. 'level1_operator' or 'supervisor'
  }) async {
    // 1. Build Intention object
    final command = ResolveAlertCommand(tripId: tripId);

    // 2. Mock Context Generation Hack (For Phase 4 Testing only)
    // The concrete AuthorizingCommandBus currently hardcodes the actor.
    // For test observability, we will temporarily pass the mock context
    // down if the Bus interface allowed it. But following pure DDD,
    // the Interceptor itself usually reaches out to an `IAuthenticationSession` port.
    //
    // Since our AuthorizingCommandBus in Phase 3 hardcoded the Context inside of it,
    // we will update that bus in a moment to accept a context from a provider.

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
      // Re-throw so the UI can show a Snackbar
      rethrow;
    }
  }
}
