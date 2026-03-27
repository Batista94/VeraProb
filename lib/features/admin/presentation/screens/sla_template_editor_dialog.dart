import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../domain/shared/money.dart';
import '../../../../domain/sla_audit/sla_penalties.dart';
import '../../../../domain/sla_audit/sla_template.dart';
import '../../../../domain/sla_audit/smart_defaults.dart';
import '../../../../domain/sla_audit/transport_vertical.dart';
import '../../../../state/providers/auth_providers.dart';
import '../../../../state/providers/sla_template_providers.dart';

/// Shows the SLA template editor dialog (INV-24: overlay modal).
///
/// Returns the saved [SlaTemplate] on success, or null on cancel.
Future<SlaTemplate?> showSlaTemplateEditorDialog(
  BuildContext context, {
  SlaTemplate? existing,
}) {
  return showDialog<SlaTemplate>(
    context: context,
    barrierDismissible: false,
    builder: (context) => SlaTemplateEditorDialog(existing: existing),
  );
}

/// Overlay modal for creating or editing an SLA template.
class SlaTemplateEditorDialog extends ConsumerStatefulWidget {
  final SlaTemplate? existing;

  const SlaTemplateEditorDialog({super.key, this.existing});

  @override
  ConsumerState<SlaTemplateEditorDialog> createState() =>
      _SlaTemplateEditorDialogState();
}

class _SlaTemplateEditorDialogState
    extends ConsumerState<SlaTemplateEditorDialog> {
  final _formKey = GlobalKey<FormState>();
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
    final p = e?.penalties;

    _nameCtl = TextEditingController(text: e?.name ?? '');
    _descCtl = TextEditingController(text: e?.description ?? '');
    _selectedVertical = e?.vertical;

    _noShowMultCtl = TextEditingController(
      text: p?.noShowPenaltyMultiplier.toString() ?? '1.5',
    );
    _delayTolCtl = TextEditingController(
      text: p?.delayToleranceMinutes.toString() ?? '15',
    );
    _delayPerMinCtl = TextEditingController(
      text: _centsToReais(p?.delayPenaltyPerMinute.cents ?? 50),
    );
    _downgradeCtl = TextEditingController(
      text: _centsToReais(p?.downgradePenaltyFlat.cents ?? 5000),
    );
    _noShowThreshCtl = TextEditingController(
      text: p?.noShowThresholdMinutes.toString() ?? '60',
    );
    _earlyArrivalCtl = TextEditingController(
      text: p?.earlyArrivalToleranceMinutes.toString() ?? '5',
    );
    _dwellCtl = TextEditingController(
      text: p?.dwellTimeMinutes.toString() ?? '3',
    );
    _graceCtl = TextEditingController(
      text: p?.gracePeriodMinutes.toString() ?? '0',
    );
    _baseTripCtl = TextEditingController(
      text: _centsToReais(p?.baseTripValue.cents ?? 0),
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
    final defaults = SmartDefaults.defaultsFor(vertical);
    _noShowMultCtl.text = defaults.noShowPenaltyMultiplier.toString();
    _delayTolCtl.text = defaults.delayToleranceMinutes.toString();
    _delayPerMinCtl.text = _centsToReais(defaults.delayPenaltyPerMinute.cents);
    _downgradeCtl.text = _centsToReais(defaults.downgradePenaltyFlat.cents);
    _noShowThreshCtl.text = defaults.noShowThresholdMinutes.toString();
    _earlyArrivalCtl.text = defaults.earlyArrivalToleranceMinutes.toString();
    _dwellCtl.text = defaults.dwellTimeMinutes.toString();
    _graceCtl.text = defaults.gracePeriodMinutes.toString();
    _baseTripCtl.text = _centsToReais(defaults.baseTripValue.cents);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (MediaQuery.sizeOf(context).width * 0.92).clamp(320.0, 660.0),
          maxHeight: (MediaQuery.sizeOf(context).height * 0.88).clamp(400.0, 740.0),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEdit ? 'Editar Modelo SLA' : 'Novo Modelo SLA',
                  style: VeraProbTypography.sectionTitle,
                ),
                const SizedBox(height: 20),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildNameAndVertical(),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _descCtl,
                          decoration: const InputDecoration(
                            labelText: 'Descrição (opcional)',
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'PARÂMETROS DE PENALIDADE',
                          style: VeraProbTypography.badge.copyWith(
                            color: VeraProbColors.textSecondary,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildPenaltyGrid(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _buildActions(isEdit),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNameAndVertical() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: _nameCtl,
            decoration: const InputDecoration(labelText: 'Nome do Modelo *'),
            autofocus: widget.existing == null,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Obrigatório';
              if (v.length > 100) return 'Máx. 100 caracteres';
              return null;
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<TransportVertical>(
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
        ),
      ],
    );
  }

  Widget _buildPenaltyGrid() {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _PenaltyField(
          controller: _noShowMultCtl,
          label: 'Multiplicador No-Show',
          suffix: 'x',
          isDecimal: true,
        ),
        _PenaltyField(
          controller: _delayTolCtl,
          label: 'Tolerância Atraso',
          suffix: 'min',
        ),
        _PenaltyField(
          controller: _delayPerMinCtl,
          label: 'Penalidade/min',
          prefix: 'R\$',
          isDecimal: true,
        ),
        _PenaltyField(
          controller: _downgradeCtl,
          label: 'Downgrade (flat)',
          prefix: 'R\$',
          isDecimal: true,
        ),
        _PenaltyField(
          controller: _noShowThreshCtl,
          label: 'Limiar No-Show',
          suffix: 'min',
        ),
        _PenaltyField(
          controller: _earlyArrivalCtl,
          label: 'Tolerância Antecipação',
          suffix: 'min',
        ),
        _PenaltyField(
          controller: _dwellCtl,
          label: 'Dwell Time',
          suffix: 'min',
        ),
        _PenaltyField(
          controller: _graceCtl,
          label: 'Período de Graça',
          suffix: 'min',
        ),
        _PenaltyField(
          controller: _baseTripCtl,
          label: 'Valor Base Viagem',
          prefix: 'R\$',
          isDecimal: true,
        ),
      ],
    );
  }

  Widget _buildActions(bool isEdit) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(isEdit ? 'Salvar' : 'Criar'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);
    try {
      final orgId = ref.read(currentOrganizationIdProvider);
      if (orgId == null) return;

      final penalties = SLAPenalties.create(
        noShowPenaltyMultiplier: double.tryParse(_noShowMultCtl.text) ?? 1.5,
        delayToleranceMinutes: int.tryParse(_delayTolCtl.text) ?? 15,
        delayPenaltyPerMinute: Money(_reaisToCents(_delayPerMinCtl.text)),
        downgradePenaltyFlat: Money(_reaisToCents(_downgradeCtl.text)),
        noShowThresholdMinutes: int.tryParse(_noShowThreshCtl.text) ?? 60,
        earlyArrivalToleranceMinutes: int.tryParse(_earlyArrivalCtl.text) ?? 5,
        dwellTimeMinutes: int.tryParse(_dwellCtl.text) ?? 3,
        gracePeriodMinutes: int.tryParse(_graceCtl.text) ?? 0,
        baseTripValue: Money(_reaisToCents(_baseTripCtl.text)),
      );

      final saved = await ref
          .read(saveSlaTemplateHandlerProvider)
          .handle(
            organizationId: orgId,
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
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar: $e'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

/// Compact penalty input field with fixed width for the grid layout.
class _PenaltyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? prefix;
  final String? suffix;
  final bool isDecimal;

  const _PenaltyField({
    required this.controller,
    required this.label,
    this.prefix,
    this.suffix,
    this.isDecimal = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
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
