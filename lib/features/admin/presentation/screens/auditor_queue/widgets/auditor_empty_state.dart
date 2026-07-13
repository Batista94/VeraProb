import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/auditor_queue_providers.dart';

class SimulateButton extends ConsumerStatefulWidget {
  final bool isNarrow;
  const SimulateButton({super.key, this.isNarrow = false});

  @override
  ConsumerState<SimulateButton> createState() => _SimulateButtonState();
}

class _SimulateButtonState extends ConsumerState<SimulateButton> {
  bool _loading = false;

  Future<void> _simulate() async {
    final messenger = ScaffoldMessenger.of(context);
    final orgId = ref.read(currentOrganizationIdProvider);
    if (orgId == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Organização não encontrada. Faça login novamente.'),
        ),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final error = await runSanctionSimulation(
        ref,
        organizationId: orgId,
        vehiclePlate: 'TST-0001',
      );
      if (error != null) {
        messenger.showSnackBar(
          SnackBar(content: Text(error), backgroundColor: VeraProbColors.error),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Sanção VEL-01 injetada — aguarde até 5s para aparecer na fila.',
            ),
          ),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Não foi possível simular a sanção. Verifique se há contratos ativos.',
          ),
          backgroundColor: VeraProbColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isNarrow) {
      return Tooltip(
        message: 'Gerar Sanção de Teste',
        child: OutlinedButton(
          onPressed: _loading ? null : _simulate,
          style: OutlinedButton.styleFrom(
            foregroundColor: VeraProbColors.textSecondary,
            side: const BorderSide(color: VeraProbColors.textDisabled),
            padding: const EdgeInsets.all(8),
            minimumSize: const Size(36, 36),
          ),
          child: _loading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.science_outlined, size: 16),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: _loading ? null : _simulate,
      icon: _loading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.science_outlined, size: 16),
      label: const Text('Gerar Sanção de Teste'),
      style: OutlinedButton.styleFrom(
        foregroundColor: VeraProbColors.textSecondary,
        side: const BorderSide(color: VeraProbColors.textDisabled),
        textStyle: VeraProbTypography.bodySmall,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
    );
  }
}
