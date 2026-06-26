import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/sla_audit/projections/sla_template_view.dart';
import 'package:veraprob/application/sla_audit/projections/penalties_form_data.dart';
import 'package:veraprob/application/sla_audit/smart_defaults_service.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/sla_template_providers.dart';

/// Shows the SLA template editor dialog (INV-24: overlay modal).
///
/// Returns the saved [SlaTemplateView] on success, or null on cancel.
Future<SlaTemplateView?> showSlaTemplateEditorDialog(
  BuildContext context, {
  SlaTemplateView? existing,
}) {
  return showDialog<SlaTemplateView>(
    context: context,
    barrierDismissible: false,
    builder: (context) => SlaTemplateEditorDialog(existing: existing),
  );
}

/// 3-step wizard overlay modal for creating or editing an SLA template.
///
/// Steps:
///   1. Identidade — name, vertical, description
///   2. Temporal — tolerances and dwell times
///   3. Financeiro — monetary penalties and multiplier
///
/// Each step has its own [GlobalKey<FormState>] for per-step validation.
/// INV-24: overlay modal (never pushed as a route).
class SlaTemplateEditorDialog extends ConsumerStatefulWidget {
  final SlaTemplateView? existing;

  const SlaTemplateEditorDialog({super.key, this.existing});

  @override
  ConsumerState<SlaTemplateEditorDialog> createState() =>
      _SlaTemplateEditorDialogState();
}

class _SlaTemplateEditorDialogState
    extends ConsumerState<SlaTemplateEditorDialog> {
  final _formKeys = [
    GlobalKey<FormState>(), // Step 1 — Identidade
    GlobalKey<FormState>(), // Step 2 — Temporal
    GlobalKey<FormState>(), // Step 3 — Financeiro
  ];
  int _currentStep = 0;
  bool _isSaving = false;

  late final TextEditingController _nameCtl;
  late final TextEditingController _descCtl;
  late final TextEditingController _noShowMultCtl;
  late final TextEditingController _delayTolCtl;
  late final TextEditingController _delayPerMinCtl;
  late final TextEditingController _downgradeCtl;
  late final TextEditingController _noShowThreshCtl;
  late final TextEditingController _earlyArrivalCtl;
  late final TextEditingController _dwellCtl;
  late final TextEditingController _graceCtl;
  late final TextEditingController _baseTripCtl;

  TransportVertical? _selectedVertical;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;

    _nameCtl = TextEditingController(text: e?.name ?? '');
    _descCtl = TextEditingController(text: e?.description ?? '');
    _selectedVertical = e?.vertical;

    _noShowMultCtl = TextEditingController(
      text: ((e?.noShowPenaltyBps ?? 15000) / 10000.0).toString(),
    );
    _delayTolCtl = TextEditingController(
      text: e?.delayToleranceMinutes.toString() ?? '15',
    );
    _delayPerMinCtl = TextEditingController(
      text: _centsToReais(e?.delayPenaltyPerMinuteCents ?? 50),
    );
    _downgradeCtl = TextEditingController(
      text: _centsToReais(e?.downgradePenaltyFlatCents ?? 5000),
    );
    _noShowThreshCtl = TextEditingController(
      text: e?.noShowThresholdMinutes.toString() ?? '60',
    );
    _earlyArrivalCtl = TextEditingController(
      text: e?.earlyArrivalToleranceMinutes.toString() ?? '5',
    );
    _dwellCtl = TextEditingController(
      text: e?.dwellTimeMinutes.toString() ?? '3',
    );
    _graceCtl = TextEditingController(
      text: e?.gracePeriodMinutes.toString() ?? '0',
    );
    _baseTripCtl = TextEditingController(
      text: _centsToReais(e?.baseTripValueCents ?? 0),
    );
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _descCtl.dispose();
    _noShowMultCtl.dispose();
    _delayTolCtl.dispose();
    _delayPerMinCtl.dispose();
    _downgradeCtl.dispose();
    _noShowThreshCtl.dispose();
    _earlyArrivalCtl.dispose();
    _dwellCtl.dispose();
    _graceCtl.dispose();
    _baseTripCtl.dispose();
    super.dispose();
  }

  String _centsToReais(int cents) {
    return (cents / 100).toStringAsFixed(2);
  }

  int _reaisToCents(String text) {
    final value = double.tryParse(text.replaceAll(',', '.')) ?? 0;
    return (value * 100).round();
  }

  void _applySmartDefaults(TransportVertical vertical) {
    final defaults = SmartDefaultsService.defaultsFor(vertical);
    _noShowMultCtl.text = (defaults.noShowPenaltyBps / 10000.0).toString();
    _delayTolCtl.text = defaults.delayToleranceMinutes.toString();
    _delayPerMinCtl.text = _centsToReais(defaults.delayPenaltyPerMinuteCents);
    _downgradeCtl.text = _centsToReais(defaults.downgradePenaltyFlatCents);
    _noShowThreshCtl.text = defaults.noShowThresholdMinutes.toString();
    _earlyArrivalCtl.text = defaults.earlyArrivalToleranceMinutes.toString();
    _dwellCtl.text = defaults.dwellTimeMinutes.toString();
    _graceCtl.text = defaults.gracePeriodMinutes.toString();
    _baseTripCtl.text = _centsToReais(defaults.baseTripValueCents);
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  void _goBack() {
    setState(() => _currentStep--);
  }

  void _handlePrimaryAction() {
    final valid = _formKeys[_currentStep].currentState?.validate() ?? false;
    if (!valid) return;
    if (_currentStep < 2) {
      setState(() => _currentStep++);
    } else {
      _save();
    }
  }

  // ── Save ────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    // Guard: prevent double-tap (Flutter Web ClickDebouncer race)
    if (_isSaving) return;

    // Capture navigator/messenger BEFORE first await — Lesson-8.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _isSaving = true);
    try {
      final orgId = ref.read(currentOrganizationIdProvider);
      if (orgId == null) return;
      final sessionId = ref.read(currentSessionIdProvider) ?? '';

      final penalties = PenaltiesFormData(
        noShowPenaltyBps:
            ((double.tryParse(_noShowMultCtl.text.replaceAll(',', '.')) ??
                        1.5) *
                    10000)
                .round(),
        delayToleranceMinutes: int.tryParse(_delayTolCtl.text) ?? 15,
        delayPenaltyPerMinuteCents: _reaisToCents(_delayPerMinCtl.text),
        downgradePenaltyFlatCents: _reaisToCents(_downgradeCtl.text),
        noShowThresholdMinutes: int.tryParse(_noShowThreshCtl.text) ?? 60,
        earlyArrivalToleranceMinutes: int.tryParse(_earlyArrivalCtl.text) ?? 5,
        dwellTimeMinutes: int.tryParse(_dwellCtl.text) ?? 3,
        gracePeriodMinutes: int.tryParse(_graceCtl.text) ?? 0,
        baseTripValueCents: _reaisToCents(_baseTripCtl.text),
      );

      final saved = await ref
          .read(saveSlaTemplateHandlerProvider)
          .handle(
            organizationId: orgId,
            sessionId: sessionId,
            name: _nameCtl.text.trim(),
            description: _descCtl.text.trim().isEmpty
                ? null
                : _descCtl.text.trim(),
            vertical: _selectedVertical,
            penalties: penalties,
            existingId: widget.existing?.id,
            existingCreatedAt: widget.existing?.createdAt,
          );

      ref.invalidate(slaTemplatesProvider);
      if (mounted) navigator.pop(SlaTemplateView.fromDomain(saved));
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Não foi possível salvar as alterações.'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return Dialog(
      backgroundColor: VeraProbColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (MediaQuery.sizeOf(context).width * 0.92).clamp(
            320.0,
            660.0,
          ),
          maxHeight: (MediaQuery.sizeOf(context).height * 0.88).clamp(
            400.0,
            600.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: _WizardHeader(currentStep: _currentStep, isEdit: isEdit),
            ),
            const Divider(height: 1, color: VeraProbColors.border),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: _buildStepContent(_currentStep),
                ),
              ),
            ),
            const Divider(height: 1, color: VeraProbColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: _buildWizardFooter(isEdit),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent(int step) {
    return Form(
      key: _formKeys[step],
      child: Column(
        key: ValueKey(step),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: switch (step) {
          0 => _buildStep1(),
          1 => _buildStep2(),
          _ => _buildStep3(),
        },
      ),
    );
  }

  // Step 1 — Identidade
  List<Widget> _buildStep1() {
    return [
      TextFormField(
        controller: _nameCtl,
        decoration: const InputDecoration(labelText: 'Nome do Modelo *'),
        autofocus: widget.existing == null,
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'Obrigatório';
          if (v.length > 100) return 'Máx. 100 caracteres';
          return null;
        },
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<TransportVertical>(
        initialValue: _selectedVertical,
        decoration: const InputDecoration(labelText: 'Vertical'),
        items: TransportVertical.values
            .map((v) => DropdownMenuItem(value: v, child: Text(v.label)))
            .toList(),
        onChanged: (v) {
          setState(() => _selectedVertical = v);
          if (v != null && v != TransportVertical.custom) {
            _applySmartDefaults(v);
          }
        },
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _descCtl,
        decoration: const InputDecoration(labelText: 'Descrição (opcional)'),
        maxLines: 2,
      ),
    ];
  }

  // Step 2 — Temporal
  List<Widget> _buildStep2() {
    return [
      _PenaltyField(
        controller: _delayTolCtl,
        label: 'Tolerância Atraso',
        suffix: 'min',
        width: double.infinity,
      ),
      const SizedBox(height: 16),
      _PenaltyField(
        controller: _noShowThreshCtl,
        label: 'Limiar No-Show',
        suffix: 'min',
        width: double.infinity,
      ),
      const SizedBox(height: 16),
      _PenaltyField(
        controller: _earlyArrivalCtl,
        label: 'Tolerância Antecipação',
        suffix: 'min',
        width: double.infinity,
      ),
      const SizedBox(height: 16),
      _PenaltyField(
        controller: _dwellCtl,
        label: 'Dwell Time',
        suffix: 'min',
        width: double.infinity,
      ),
      const SizedBox(height: 16),
      _PenaltyField(
        controller: _graceCtl,
        label: 'Período de Graça',
        suffix: 'min',
        width: double.infinity,
      ),
    ];
  }

  // Step 3 — Financeiro
  List<Widget> _buildStep3() {
    return [
      _PenaltyField(
        controller: _delayPerMinCtl,
        label: 'Penalidade/min',
        prefix: r'R$',
        isDecimal: true,
        width: double.infinity,
      ),
      const SizedBox(height: 16),
      _PenaltyField(
        controller: _downgradeCtl,
        label: 'Downgrade (flat)',
        prefix: r'R$',
        isDecimal: true,
        width: double.infinity,
      ),
      const SizedBox(height: 16),
      _PenaltyField(
        controller: _noShowMultCtl,
        label: 'Multiplicador No-Show',
        suffix: 'x',
        isDecimal: true,
        width: double.infinity,
      ),
      const SizedBox(height: 16),
      _PenaltyField(
        controller: _baseTripCtl,
        label: 'Valor Base Viagem',
        prefix: r'R$',
        isDecimal: true,
        width: double.infinity,
      ),
    ];
  }

  Widget _buildWizardFooter(bool isEdit) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        Row(
          children: [
            if (_currentStep > 0) ...[
              OutlinedButton(
                onPressed: _isSaving ? null : _goBack,
                style: OutlinedButton.styleFrom(
                  foregroundColor: VeraProbColors.textSecondary,
                  side: const BorderSide(color: VeraProbColors.border),
                ),
                child: const Text('Anterior'),
              ),
              const SizedBox(width: 12),
            ],
            FilledButton(
              onPressed: _isSaving ? null : _handlePrimaryAction,
              child: _currentStep < 2
                  ? const Text('Próximo')
                  : (_isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(
                                VeraProbColors.background,
                              ),
                            ),
                          )
                        : Text(isEdit ? 'Salvar' : 'Criar')),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Header + Step Indicator ──────────────────────────────────────────────────

class _WizardHeader extends StatelessWidget {
  final int currentStep;
  final bool isEdit;

  const _WizardHeader({required this.currentStep, required this.isEdit});

  static const _stepLabels = ['Identidade', 'Temporal', 'Financeiro'];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isEdit ? 'Editar Modelo SLA' : 'Novo Modelo SLA',
          style: VeraProbTypography.sectionTitle,
        ),
        const SizedBox(height: 4),
        Text(
          'Passo ${currentStep + 1} de 3 — ${_stepLabels[currentStep]}',
          style: VeraProbTypography.caption.copyWith(
            color: VeraProbColors.textSecondary,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            for (int i = 0; i < 3; i++) ...[
              _StepDot(
                number: i + 1,
                state: i < currentStep
                    ? _StepState.completed
                    : i == currentStep
                    ? _StepState.active
                    : _StepState.pending,
              ),
              if (i < 2) _StepConnector(active: currentStep > i),
            ],
          ],
        ),
      ],
    );
  }
}

enum _StepState { completed, active, pending }

class _StepDot extends StatelessWidget {
  final int number;
  final _StepState state;

  const _StepDot({required this.number, required this.state});

  @override
  Widget build(BuildContext context) {
    final isActive = state == _StepState.active;
    final isCompleted = state == _StepState.completed;

    final bg = isActive || isCompleted
        ? VeraProbColors.primary
        : VeraProbColors.surfaceElevated;
    final fgColor = isActive || isCompleted
        ? VeraProbColors.background
        : VeraProbColors.textDisabled;

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: isActive
            ? Border.all(
                color: VeraProbColors.primary.withValues(alpha: 0.3),
                width: 3,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: isCompleted
          ? const Icon(Icons.check, size: 14, color: VeraProbColors.background)
          : Text(
              '$number',
              style: VeraProbTypography.badge.copyWith(
                color: fgColor,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

class _StepConnector extends StatelessWidget {
  final bool active;

  const _StepConnector({required this.active});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 1,
        color: active ? VeraProbColors.primary : VeraProbColors.border,
        margin: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }
}

// ── Penalty Input Field ──────────────────────────────────────────────────────

/// Compact penalty input with fixed or flexible width.
class _PenaltyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? prefix;
  final String? suffix;
  final bool isDecimal;

  /// Width of the field. Use [double.infinity] for full-width in wizard steps.
  final double width;

  const _PenaltyField({
    required this.controller,
    required this.label,
    this.prefix,
    this.suffix,
    this.isDecimal = false,
    this.width = 180,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixText: prefix,
          suffixText: suffix,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
        keyboardType: TextInputType.numberWithOptions(decimal: isDecimal),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            isDecimal ? RegExp(r'[\d.,]') : RegExp(r'\d'),
          ),
        ],
        validator: (v) {
          if (v == null || v.isEmpty) return 'Obrigatório';
          return null;
        },
      ),
    );
  }
}
