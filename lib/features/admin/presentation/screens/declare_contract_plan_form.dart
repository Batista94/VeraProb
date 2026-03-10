import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:busflow/application/sla_audit/contractual_service_input.dart';
import 'package:busflow/application/sla_audit/declare_contractual_plan_command.dart';
import 'package:busflow/domain/sla_audit/domain_exception.dart';
import 'package:busflow/state/providers/auth_providers.dart';
import 'package:busflow/state/providers/contract_providers.dart';
import 'package:busflow/state/providers/sla_providers.dart';

final _currencyFormat = NumberFormat.currency(
  locale: 'pt_BR',
  symbol: r'R$',
  decimalDigits: 2,
);

/// Dialog form for declaring a new [PlanDeclaration] for an existing contract.
///
/// Each SET is a "Viagem Programada" (the term SET is internal to the domain).
/// Computes SHA-256 of the serialized command JSON as [originalFileHash].
///
/// Usage: `await DeclareContractPlanForm.show(context, ref, contractId: id)`
/// Returns `true` if plan was declared successfully, `false` otherwise.
class DeclareContractPlanForm extends ConsumerStatefulWidget {
  final String contractId;
  final String contractName;

  const DeclareContractPlanForm({
    super.key,
    required this.contractId,
    required this.contractName,
  });

  static Future<bool?> show(
    BuildContext context,
    WidgetRef ref, {
    required String contractId,
    required String contractName,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DeclareContractPlanForm(
        contractId: contractId,
        contractName: contractName,
      ),
    );
  }

  @override
  ConsumerState<DeclareContractPlanForm> createState() =>
      _DeclareContractPlanFormState();
}

class _DeclareContractPlanFormState
    extends ConsumerState<DeclareContractPlanForm> {
  final List<_SetFormState> _sets = [];
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _sets.add(_SetFormState()); // Start with one SET
  }

  @override
  void dispose() {
    for (final s in _sets) {
      s.dispose();
    }
    super.dispose();
  }

  void _addSet() {
    if (_sets.length >= 50) {
      setState(
        () => _errorMessage = 'Limite de 50 viagens programadas por plano.',
      );
      return;
    }
    setState(() => _sets.add(_SetFormState()));
  }

  void _removeSet(int index) {
    if (_sets.length <= 1) return; // Must keep at least one
    _sets[index].dispose();
    setState(() => _sets.removeAt(index));
  }

  /// Generates a deterministic SHA-256 hash of the command payload.
  /// Keys are sorted alphabetically to guarantee determinism (SE-3).
  String _computeHash(List<ContractualServiceInput> services) {
    final payload = {
      'contract_id': widget.contractId,
      'services': services
          .map(
            (s) => {
              'end_latitude': s.endLatitude,
              'end_longitude': s.endLongitude,
              'end_radius_meters': s.endRadiusMeters,
              'contractual_value': s.contractualValue,
              'no_show_penalty_multiplier': s.noShowPenaltyMultiplier,
              'scheduled_end_time_utc': s.scheduledEndTimeUtc.toIso8601String(),
              'scheduled_start_time_utc':
                  s.scheduledStartTimeUtc.toIso8601String(),
              'start_latitude': s.startLatitude,
              'start_longitude': s.startLongitude,
              'start_radius_meters': s.startRadiusMeters,
            },
          )
          .toList(),
    };
    final json = jsonEncode(payload);
    return sha256.convert(utf8.encode(json)).toString();
  }

  Future<void> _submit() async {
    // Validate all sets
    for (int i = 0; i < _sets.length; i++) {
      final err = _sets[i].validate();
      if (err != null) {
        setState(() => _errorMessage = 'Viagem ${i + 1}: $err');
        return;
      }
    }

    final organizationId = ref.read(currentOrganizationIdProvider);
    final operatorId = ref.read(currentOperatorIdProvider);
    if (organizationId == null || operatorId == null) {
      setState(() => _errorMessage = 'Sessão inválida. Faça login novamente.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      // Build service inputs
      final services = _sets.map((s) => s.toInput()).toList();

      // Compute next plan version
      final planRepo = ref.read(planDeclarationRepositoryProvider);
      final existing = await planRepo.findByContract(
        widget.contractId,
        organizationId: organizationId,
      );
      final nextVersion =
          existing.isEmpty ? 1 : existing.map((p) => p.planVersion).reduce((a, b) => a > b ? a : b) + 1;

      // Compute deterministic hash (SE-3)
      final originalFileHash = _computeHash(services);

      final handler = ref.read(declareContractualPlanHandlerProvider);

      await handler.handle(
        DeclareContractualPlanCommand(
          organizationId: organizationId,
          contractId: widget.contractId,
          declaredByUserId: operatorId,
          planVersion: nextVersion,
          originalFileHash: originalFileHash,
          declaredAtUtc: DateTime.now().toUtc(),
          services: services,
        ),
      );

      if (mounted) Navigator.of(context).pop(true);
    } on DomainException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Erro inesperado: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalValue = _sets.fold(
      0.0,
      (sum, s) => sum + (double.tryParse(s.valueController.text) ?? 0),
    );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.playlist_add_check_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Declarar Plano',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          widget.contractName,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(false),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
              const Divider(height: 20),

              // SET list header
              Row(
                children: [
                  const Text(
                    'Viagens Programadas',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_sets.length}/50',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Adicionar Viagem'),
                    onPressed: _addSet,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // SET rows
              Expanded(
                child: ListView.builder(
                  itemCount: _sets.length,
                  itemBuilder: (context, index) => _SetRow(
                    index: index,
                    state: _sets[index],
                    canRemove: _sets.length > 1,
                    onRemove: () => _removeSet(index),
                    onChanged: () => setState(() {}),
                  ),
                ),
              ),

              const Divider(height: 20),

              // Summary + warning
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_sets.length} viagem(ns) · Valor total: ${_currencyFormat.format(totalValue)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '⚠️  Plano publicado não pode ser editado. Uma nova versão deverá ser declarada.',
                          style: TextStyle(fontSize: 11, color: Colors.orange),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Error message
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.publish, size: 16),
                    label: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Publicar Plano'),
                    onPressed: _isSubmitting ? null : _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── SET form state & row ──────────────────────────────────────────────────────

class _SetFormState {
  final TextEditingController startController = TextEditingController();
  final TextEditingController endController = TextEditingController();
  final TextEditingController startLatController = TextEditingController();
  final TextEditingController startLngController = TextEditingController();
  final TextEditingController startRadiusController =
      TextEditingController(text: '200');
  final TextEditingController endLatController = TextEditingController();
  final TextEditingController endLngController = TextEditingController();
  final TextEditingController endRadiusController =
      TextEditingController(text: '200');
  final TextEditingController valueController = TextEditingController();
  final TextEditingController multiplierController =
      TextEditingController(text: '1.5');

  void dispose() {
    startController.dispose();
    endController.dispose();
    startLatController.dispose();
    startLngController.dispose();
    startRadiusController.dispose();
    endLatController.dispose();
    endLngController.dispose();
    endRadiusController.dispose();
    valueController.dispose();
    multiplierController.dispose();
  }

  String? validate() {
    if (startController.text.trim().isEmpty) return 'Início programado obrigatório.';
    if (endController.text.trim().isEmpty) return 'Fim programado obrigatório.';
    final startLat = double.tryParse(startLatController.text);
    final startLng = double.tryParse(startLngController.text);
    final endLat = double.tryParse(endLatController.text);
    final endLng = double.tryParse(endLngController.text);
    if (startLat == null || startLat < -90 || startLat > 90) {
      return 'Latitude de partida inválida (−90 a 90).';
    }
    if (startLng == null || startLng < -180 || startLng > 180) {
      return 'Longitude de partida inválida (−180 a 180).';
    }
    if (endLat == null || endLat < -90 || endLat > 90) {
      return 'Latitude de chegada inválida (−90 a 90).';
    }
    if (endLng == null || endLng < -180 || endLng > 180) {
      return 'Longitude de chegada inválida (−180 a 180).';
    }
    if ((double.tryParse(valueController.text) ?? 0) <= 0) {
      return 'Valor contratual deve ser maior que zero.';
    }
    return null;
  }

  ContractualServiceInput toInput() {
    final start = DateTime.parse(startController.text.trim());
    final end = DateTime.parse(endController.text.trim());
    return ContractualServiceInput(
      scheduledStartTimeUtc: start.isUtc ? start : start.toUtc(),
      scheduledEndTimeUtc: end.isUtc ? end : end.toUtc(),
      startLatitude: double.parse(startLatController.text),
      startLongitude: double.parse(startLngController.text),
      startRadiusMeters: int.tryParse(startRadiusController.text) ?? 200,
      endLatitude: double.parse(endLatController.text),
      endLongitude: double.parse(endLngController.text),
      endRadiusMeters: int.tryParse(endRadiusController.text) ?? 200,
      contractualValue: double.parse(valueController.text),
      noShowPenaltyMultiplier:
          double.tryParse(multiplierController.text) ?? 1.5,
    );
  }
}

class _SetRow extends StatelessWidget {
  final int index;
  final _SetFormState state;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _SetRow({
    required this.index,
    required this.state,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row header
            Row(
              children: [
                Text(
                  'Viagem ${index + 1}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const Spacer(),
                if (canRemove)
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 16, color: Colors.red),
                    onPressed: onRemove,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Remover viagem',
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Timestamps row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: state.startController,
                    onChanged: (_) => onChanged(),
                    decoration: const InputDecoration(
                      labelText: 'Início UTC (ISO)',
                      hintText: '2026-03-15T06:00:00.000Z',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: state.endController,
                    onChanged: (_) => onChanged(),
                    decoration: const InputDecoration(
                      labelText: 'Fim UTC (ISO)',
                      hintText: '2026-03-15T07:00:00.000Z',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Geofences
            Row(
              children: [
                Expanded(
                  child: _NumField(
                    label: 'Lat. Partida',
                    controller: state.startLatController,
                    onChanged: onChanged,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _NumField(
                    label: 'Lng. Partida',
                    controller: state.startLngController,
                    onChanged: onChanged,
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 80,
                  child: _NumField(
                    label: 'Raio (m)',
                    controller: state.startRadiusController,
                    onChanged: onChanged,
                    isInt: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _NumField(
                    label: 'Lat. Chegada',
                    controller: state.endLatController,
                    onChanged: onChanged,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _NumField(
                    label: 'Lng. Chegada',
                    controller: state.endLngController,
                    onChanged: onChanged,
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 80,
                  child: _NumField(
                    label: 'Raio (m)',
                    controller: state.endRadiusController,
                    onChanged: onChanged,
                    isInt: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Financial
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: state.valueController,
                    onChanged: (_) => onChanged(),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Valor (R\$)',
                      prefixText: 'R\$ ',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 120,
                  child: _NumField(
                    label: 'Mult. No-Show',
                    controller: state.multiplierController,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NumField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;
  final bool isInt;

  const _NumField({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.isInt = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: (_) => onChanged(),
      keyboardType: TextInputType.numberWithOptions(
        decimal: !isInt,
        signed: true,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          isInt ? RegExp(r'^\d+') : RegExp(r'^-?\d+\.?\d*'),
        ),
      ],
      decoration: InputDecoration(labelText: label, isDense: true),
    );
  }
}
