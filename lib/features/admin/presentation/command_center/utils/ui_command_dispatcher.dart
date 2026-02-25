import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:busflow/application/authority/operational_command_bus.dart';
import 'package:busflow/domain/authority/commands/operational_command.dart';
import 'package:busflow/state/providers/authority_providers.dart';

/// Centralized utility to dispatch operational commands from the UI.
///
/// It encapsulates the `AuthorizingCommandBus`, catches `UnauthorizedActionException`
/// or other errors, and displays a normalized `SnackBar` (toast) to the user.
/// This prevents repetitive try/catch logic spread across all action buttons.
class UiCommandDispatcher {
  static Future<bool> dispatch(
    BuildContext context,
    WidgetRef ref,
    OperationalCommand command,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final bus = ref.read(operationalCommandBusProvider);

    try {
      // Execute the authority flow + mutation
      await bus.dispatch(command);

      // Feedback for APPROVED
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Ação autorizada e registrada.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          backgroundColor: Color(0xFF2E7D32), // Green
          duration: Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
        ),
      );

      return true; // Success
    } on UnauthorizedActionException catch (e) {
      // Feedback for DENIED
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            'Acesso Negado: Ação registrada no ledger.\nMotivo: ${e.reason}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: const Color(0xFFD32F2F), // Red
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    } catch (e) {
      // Unexpected Runtime Crash
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            'Erro interno ao despachar comando: $e',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.black87,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }
  }
}
