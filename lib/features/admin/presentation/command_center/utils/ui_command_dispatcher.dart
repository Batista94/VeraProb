import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/application/authority/operational_command_bus.dart';
import 'package:veraprob/application/authority/operational_command_bus.dart'
    show OperationalCommand, UnauthorizedActionException;
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/authority_providers.dart';

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
            // ACCENT-FILL-CONTRAST: dark foreground on accent fill.
            style: TextStyle(
              color: VeraProbColors.background,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: VeraProbColors.success,
          duration: Duration(milliseconds: 1500),
          behavior: SnackBarBehavior.floating,
        ),
      );

      return true; // Success
    } on UnauthorizedActionException catch (e) {
      // Feedback for DENIED — e.reason is a typed domain field, not raw exception
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            'Acesso Negado: Ação registrada no ledger.\nMotivo: ${e.reason}',
            // ACCENT-FILL-CONTRAST: dark foreground on accent fill.
            style: const TextStyle(
              color: VeraProbColors.background,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: VeraProbColors.error,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    } catch (_) {
      // Unexpected runtime error — do not expose internals to the UI
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Falha ao executar o comando operacional. Tente novamente.',
          ),
          duration: Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }
  }
}
