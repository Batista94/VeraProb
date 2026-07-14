import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/presentation/sandbox/providers/sandbox_wizard_provider.dart';
import 'package:veraprob/presentation/sandbox/validators/sandbox_wizard_validator.dart';
import 'package:veraprob/presentation/shared/formatters/brl_currency_input_formatter.dart';
import 'package:veraprob/presentation/theme/sandbox_theme_extension.dart';
import 'package:veraprob/state/providers/sandbox_providers.dart';

/// Contract option for the wizard dropdown (keeps UI free of infra models).
class SandboxContractOption {
  final String id;
  final String label;

  const SandboxContractOption({required this.id, required this.label});
}

/// Single-page SLA Sandbox creation form (session, period, rules, financial).
///
/// "Executar Simulação" stays disabled until [SandboxWizardState.isValid].
/// On success, [onSimulationStarted] receives the new session UUID.
///
/// When [lockedContractId] is set, the contract dropdown is hidden and the
/// form asserts the provider state matches before submission (URL-tamper guard).
class SandboxWizardForm extends ConsumerStatefulWidget {
  final List<SandboxContractOption> contracts;
  final String? lockedContractId;
  final ValueChanged<String>? onSimulationStarted;

  const SandboxWizardForm({
    super.key,
    required this.contracts,
    this.lockedContractId,
    this.onSimulationStarted,
  });

  @override
  ConsumerState<SandboxWizardForm> createState() => _SandboxWizardFormState();
}

class _SandboxWizardFormState extends ConsumerState<SandboxWizardForm> {
  late final TextEditingController _sessionController;
  late final TextEditingController _capController;
  late final TextEditingController _baseFineController;
  bool _submitting = false;

  bool get _isLocked => widget.lockedContractId != null;

  @override
  void initState() {
    super.initState();
    _sessionController = TextEditingController();
    _capController = TextEditingController();
    _baseFineController = TextEditingController();

    if (_isLocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(sandboxWizardProvider.notifier)
            .setContractId(widget.lockedContractId);
      });
    }
  }

  @override
  void dispose() {
    _sessionController.dispose();
    _capController.dispose();
    _baseFineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sandboxWizardProvider);
    final simAsync = ref.watch(sandboxSimulationControllerProvider);
    final busy = _submitting || simAsync.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle(title: 'Sessão', color: SandboxTokens.accentColor),
        TextField(
          controller: _sessionController,
          decoration: const InputDecoration(
            labelText: 'Nome da sessão',
            hintText: 'Ex.: Teste Tolerância 15min',
          ),
          onChanged: (v) =>
              ref.read(sandboxWizardProvider.notifier).setSessionLabel(v),
        ),
        const SizedBox(height: VeraProbSpacing.sm),
        if (_isLocked)
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Contrato'),
            child: Text(
              widget.contracts.isNotEmpty
                  ? widget.contracts.first.label
                  : widget.lockedContractId!,
              style: VeraProbTypography.bodyMedium,
            ),
          )
        else
          DropdownButtonFormField<String>(
            // ignore: deprecated_member_use — value is the stable API in this Flutter pin
            value: state.contractId,
            decoration: const InputDecoration(labelText: 'Contrato'),
            items: widget.contracts
                .map((c) => DropdownMenuItem(value: c.id, child: Text(c.label)))
                .toList(),
            onChanged: busy
                ? null
                : (id) => ref
                      .read(sandboxWizardProvider.notifier)
                      .setContractId(id),
          ),
        const SizedBox(height: VeraProbSpacing.lg),
        const _SectionTitle(title: 'Período', color: SandboxTokens.accentColor),
        Text(
          'Máximo ${SandboxWizardValidator.maxPeriod.inDays} dias (6 meses).',
          style: VeraProbTypography.caption,
        ),
        const SizedBox(height: VeraProbSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _DateField(
                label: 'Início (UTC)',
                value: state.periodStartUtc,
                onPick: (d) => ref
                    .read(sandboxWizardProvider.notifier)
                    .setPeriod(startUtc: d),
              ),
            ),
            const SizedBox(width: VeraProbSpacing.sm),
            Expanded(
              child: _DateField(
                label: 'Fim (UTC)',
                value: state.periodEndUtc,
                onPick: (d) => ref
                    .read(sandboxWizardProvider.notifier)
                    .setPeriod(endUtc: d),
              ),
            ),
          ],
        ),
        const SizedBox(height: VeraProbSpacing.lg),
        const _SectionTitle(title: 'Regras', color: SandboxTokens.accentColor),
        Text(
          'Tolerância de atraso: ${state.delayToleranceMinutes ?? 15} min',
          style: VeraProbTypography.bodySmall,
        ),
        Slider(
          value: (state.delayToleranceMinutes ?? 15).toDouble().clamp(1, 120),
          min: 1,
          max: 120,
          divisions: 119,
          label: '${state.delayToleranceMinutes ?? 15} min',
          activeColor: SandboxTokens.accentColor,
          onChanged: busy
              ? null
              : (v) => ref
                    .read(sandboxWizardProvider.notifier)
                    .setDelayToleranceMinutes(v),
        ),
        const SizedBox(height: VeraProbSpacing.lg),
        const _SectionTitle(
          title: 'Financeiro',
          color: SandboxTokens.accentColor,
        ),
        TextField(
          controller: _capController,
          decoration: const InputDecoration(
            labelText: 'Teto mensal de multas (opcional)',
            hintText: 'R\$ 5.000,00',
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [BrlCurrencyInputFormatter()],
          onChanged: (v) => ref
              .read(sandboxWizardProvider.notifier)
              .setMonthlyPenaltyCapFromMasked(v),
        ),
        const SizedBox(height: VeraProbSpacing.sm),
        TextField(
          controller: _baseFineController,
          decoration: const InputDecoration(
            labelText: 'Multa base (opcional)',
            hintText: 'R\$ 150,00',
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [BrlCurrencyInputFormatter()],
          onChanged: (v) =>
              ref.read(sandboxWizardProvider.notifier).setBaseFineFromMasked(v),
        ),
        if (state.validationErrors.isNotEmpty) ...[
          const SizedBox(height: VeraProbSpacing.md),
          ...state.validationErrors.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: VeraProbSpacing.xs),
              child: Text(
                e,
                style: VeraProbTypography.caption.copyWith(
                  color: VeraProbColors.error,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: VeraProbSpacing.lg),
        FilledButton(
          onPressed: (!state.isValid || busy) ? null : _onExecute,
          style: FilledButton.styleFrom(
            backgroundColor: SandboxTokens.accentColor,
            foregroundColor: VeraProbColors.background,
          ),
          child: busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Executar Simulação'),
        ),
      ],
    );
  }

  Future<void> _onExecute() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _submitting = true);
    try {
      final state = ref.read(sandboxWizardProvider);
      final locked = widget.lockedContractId;
      if (locked != null && state.contractId != locked) {
        throw const IntegrityException('URL Tampering detected');
      }

      final sessionId = await ref
          .read(sandboxWizardProvider.notifier)
          .executeSimulation();
      if (!mounted) return;
      if (sessionId != null) {
        widget.onSimulationStarted?.call(sessionId);
      }
    } on IntegrityException {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Contrato inválido para esta simulação. Recarregue a página.',
          ),
          backgroundColor: VeraProbColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final Color color;

  const _SectionTitle({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: VeraProbSpacing.sm),
      child: Text(
        title,
        style: VeraProbTypography.sectionTitle.copyWith(color: color),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onPick;

  const _DateField({
    required this.label,
    required this.value,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? 'Selecionar'
        : '${value!.day.toString().padLeft(2, '0')}/'
              '${value!.month.toString().padLeft(2, '0')}/'
              '${value!.year}';

    return OutlinedButton(
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.utc(2026, 1, 1),
          firstDate: DateTime.utc(2020),
          lastDate: DateTime.utc(2035),
        );
        if (picked == null) return;
        onPick(DateTime.utc(picked.year, picked.month, picked.day));
      },
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text('$label\n$text', style: VeraProbTypography.bodySmall),
      ),
    );
  }
}
