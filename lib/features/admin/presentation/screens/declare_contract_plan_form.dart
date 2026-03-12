import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:busflow/application/sla_audit/declare_contractual_plan_command.dart';
import 'package:busflow/core/theme/app_theme.dart';
import 'package:busflow/domain/sla_audit/domain_exception.dart';
import 'package:busflow/domain/sla_audit/operational_zone.dart';
import 'package:busflow/domain/sla_audit/shift_pattern.dart';
import 'package:busflow/domain/sla_audit/sla_penalties.dart';
import 'package:busflow/domain/sla_audit/vehicle_category.dart';
import 'package:busflow/domain/shared/money.dart';
import 'package:busflow/state/providers/auth_providers.dart';
import 'package:busflow/state/providers/contract_providers.dart';
import 'package:busflow/state/providers/operational_zone_providers.dart';
import 'package:busflow/state/providers/sla_providers.dart';

// ── BR Timezones (curated list for dropdown) ──────────────────
const _kBrTimezones = [
  'America/Sao_Paulo',
  'America/Manaus',
  'America/Belem',
  'America/Fortaleza',
  'America/Recife',
  'America/Noronha',
  'America/Cuiaba',
  'America/Porto_Velho',
  'America/Rio_Branco',
  'America/Boa_Vista',
];

/// Immutable snapshot of one fully configured shift turn (Steps 1-3).
///
/// Created when the operator clicks "+ Adicionar Turno de Retorno" to save
/// the current draft before configuring the next turn. The final turn is
/// never stored here — it's read from the live form controllers in [_submit].
class _ShiftDraftSnapshot {
  final String originZoneId;
  final String destinationZoneId;
  final String originZoneName;
  final String destinationZoneName;
  final Set<int> selectedDays;
  final TimeOfDay arrivalTime;
  final TimeOfDay departureTime;
  final String timezone;
  final VehicleCategory requiredVehicleCategory;
  final int baseValueCents;
  final int delayToleranceMinutes;
  final int earlyArrivalToleranceMinutes;
  final int dwellTimeMinutes;
  final double noShowMultiplier;
  final int noShowThresholdMinutes;
  final int delayPenaltyCentsPerMinute;
  final int downgradePenaltyCents;

  const _ShiftDraftSnapshot({
    required this.originZoneId,
    required this.destinationZoneId,
    required this.originZoneName,
    required this.destinationZoneName,
    required this.selectedDays,
    required this.arrivalTime,
    required this.departureTime,
    required this.timezone,
    required this.requiredVehicleCategory,
    required this.baseValueCents,
    required this.delayToleranceMinutes,
    required this.earlyArrivalToleranceMinutes,
    required this.dwellTimeMinutes,
    required this.noShowMultiplier,
    required this.noShowThresholdMinutes,
    required this.delayPenaltyCentsPerMinute,
    required this.downgradePenaltyCents,
  });
}

/// Dialog form for declaring a new B2B Plan for an existing contract.
///
/// Supports declaring multiple [ShiftPattern]s (e.g., round-trip) in a
/// single wizard session by accumulating confirmed turns via [_ShiftDraftSnapshot].
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
  int _currentStep = 0;
  bool _isSubmitting = false;
  String? _errorMessage;

  // ── Round-trip: accumulator of confirmed turns ───────────────
  final List<_ShiftDraftSnapshot> _confirmedShiftDrafts = [];

  // ── Step 1: Zonas Operacionais ───────────────────────────────
  String? _selectedOriginZoneId;
  String? _selectedDestinationZoneId;

  // ── Step 2: Padrão de Turno ──────────────────────────────────
  final Set<int> _selectedDays = {1, 2, 3, 4, 5}; // Seg-Sex
  TimeOfDay? _arrivalTime;
  TimeOfDay? _departureTime;
  String _timezone = 'America/Sao_Paulo';
  VehicleCategory _requiredVehicleCategory = VehicleCategory.conventional;

  // ── Step 3: SLA & Penalidades ────────────────────────────────
  final TextEditingController _baseValueController = TextEditingController();

  // Grupo 1 — Pontualidade e Janelas Operacionais
  final TextEditingController _delayToleranceController =
      TextEditingController(text: '15');
  final TextEditingController _earlyArrivalToleranceController =
      TextEditingController(text: '5');
  final TextEditingController _dwellTimeController =
      TextEditingController(text: '3');

  // Grupo 2 — Falhas Críticas
  final TextEditingController _noShowMultiplierController =
      TextEditingController(text: '1,5');
  final TextEditingController _noShowThresholdController =
      TextEditingController(text: '60');

  // Grupo 3 — Qualidade da Frota
  final TextEditingController _delayMinuteValueController =
      TextEditingController(text: '0,50');
  final TextEditingController _downgradeValueController =
      TextEditingController(text: '50,00');

  @override
  void initState() {
    super.initState();
    _baseValueController.addListener(_clearError);
    _delayToleranceController.addListener(_clearError);
    _earlyArrivalToleranceController.addListener(_clearError);
    _dwellTimeController.addListener(_clearError);
    _noShowMultiplierController.addListener(_clearError);
    _noShowThresholdController.addListener(_clearError);
    _delayMinuteValueController.addListener(_clearError);
    _downgradeValueController.addListener(_clearError);
  }

  void _clearError() {
    if (_errorMessage != null) setState(() => _errorMessage = null);
  }

  @override
  void dispose() {
    _baseValueController.dispose();
    _delayToleranceController.dispose();
    _earlyArrivalToleranceController.dispose();
    _dwellTimeController.dispose();
    _noShowMultiplierController.dispose();
    _noShowThresholdController.dispose();
    _delayMinuteValueController.dispose();
    _downgradeValueController.dispose();
    super.dispose();
  }

  // ── Financial helpers ────────────────────────────────────────

  int _parseReaisToCents(String value) {
    if (value.trim().isEmpty) return 0;
    final clean = value.replaceAll('.', '').replaceAll(',', '.');
    final doubleVal = double.tryParse(clean) ?? 0.0;
    return (doubleVal * 100).round();
  }

  double _parseDouble(String value) {
    if (value.trim().isEmpty) return 0.0;
    final clean = value.replaceAll(',', '.');
    return double.tryParse(clean) ?? 0.0;
  }

  String _formatTime(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatCents(int cents) {
    final reais = cents / 100.0;
    return 'R\$ ${reais.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  String _formatDays(Set<int> days) {
    const map = {1: 'Seg', 2: 'Ter', 3: 'Qua', 4: 'Qui', 5: 'Sex', 6: 'Sáb', 7: 'Dom'};
    final sorted = days.toList()..sort();
    return sorted.map((d) => map[d] ?? '?').join(', ');
  }

  // ── Snapshot helpers ─────────────────────────────────────────

  /// Resolves zone names from the loaded provider or falls back to the ID.
  String _zoneName(String? id, List<OperationalZone> zones) {
    if (id == null) return '?';
    return zones.where((z) => z.id == id).firstOrNull?.name ?? id;
  }

  /// Captures current form state (Steps 1-3) as an immutable snapshot.
  _ShiftDraftSnapshot _snapshotCurrentDraft(List<OperationalZone> zones) {
    return _ShiftDraftSnapshot(
      originZoneId: _selectedOriginZoneId!,
      destinationZoneId: _selectedDestinationZoneId!,
      originZoneName: _zoneName(_selectedOriginZoneId, zones),
      destinationZoneName: _zoneName(_selectedDestinationZoneId, zones),
      selectedDays: Set.of(_selectedDays),
      arrivalTime: _arrivalTime!,
      departureTime: _departureTime!,
      timezone: _timezone,
      requiredVehicleCategory: _requiredVehicleCategory,
      baseValueCents: _parseReaisToCents(_baseValueController.text),
      delayToleranceMinutes: int.tryParse(_delayToleranceController.text) ?? 15,
      earlyArrivalToleranceMinutes:
          int.tryParse(_earlyArrivalToleranceController.text) ?? 5,
      dwellTimeMinutes: int.tryParse(_dwellTimeController.text) ?? 3,
      noShowMultiplier: _parseDouble(_noShowMultiplierController.text),
      noShowThresholdMinutes: int.tryParse(_noShowThresholdController.text) ?? 60,
      delayPenaltyCentsPerMinute:
          _parseReaisToCents(_delayMinuteValueController.text),
      downgradePenaltyCents: _parseReaisToCents(_downgradeValueController.text),
    );
  }

  /// Resets Steps 2–3 fields for the next shift (e.g. return trip).
  /// Swaps origin/destination zones to pre-fill the reverse route.
  void _resetForReturnShift() {
    final swappedOrigin = _selectedDestinationZoneId;
    final swappedDest = _selectedOriginZoneId;
    setState(() {
      _selectedOriginZoneId = swappedOrigin;
      _selectedDestinationZoneId = swappedDest;
      // Reset time (reverse trip typically departs later)
      _arrivalTime = null;
      _departureTime = null;
      // Keep days, timezone and category from previous turn (user may modify)
    });
    _baseValueController.text = '';
    // Reset SLA to defaults (user typically re-enters for return trip)
    _delayToleranceController.text = '15';
    _earlyArrivalToleranceController.text = '5';
    _dwellTimeController.text = '3';
    _noShowMultiplierController.text = '1,5';
    _noShowThresholdController.text = '60';
    _delayMinuteValueController.text = '0,50';
    _downgradeValueController.text = '50,00';
  }

  // ── Stepper Navigation ───────────────────────────────────────

  void _onStepContinue() {
    if (_currentStep == 0) {
      if (_selectedOriginZoneId == null || _selectedDestinationZoneId == null) {
        setState(() => _errorMessage =
            'Selecione a Zona de Partida e a Zona de Chegada para continuar.');
        return;
      }
      if (_selectedOriginZoneId == _selectedDestinationZoneId) {
        setState(() => _errorMessage =
            'A Zona de Partida e Chegada devem ser diferentes.');
        return;
      }
    } else if (_currentStep == 1) {
      if (_selectedDays.isEmpty) {
        setState(() => _errorMessage =
            'Selecione ao menos um dia da semana para o turno.');
        return;
      }
      if (_arrivalTime == null || _departureTime == null) {
        setState(() => _errorMessage =
            'Defina os horários de Chegada e Partida do turno.');
        return;
      }
    } else if (_currentStep == 2) {
      final baseVal = _parseReaisToCents(_baseValueController.text);
      if (baseVal <= 0) {
        setState(() => _errorMessage =
            'O valor base da viagem contratada não pode ser zero.');
        return;
      }
    }

    setState(() {
      _errorMessage = null;
      if (_currentStep < 3) {
        _currentStep++;
      } else {
        _submit();
      }
    });
  }

  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() {
        _errorMessage = null;
        _currentStep--;
      });
    } else {
      Navigator.of(context).pop(false);
    }
  }

  /// Saves current draft as a confirmed turn and resets Steps 2-3 for a return shift.
  void _addReturnShift() {
    if (_currentStep != 2) return;
    final baseVal = _parseReaisToCents(_baseValueController.text);
    if (baseVal <= 0) {
      setState(() => _errorMessage =
          'O valor base da viagem contratada não pode ser zero antes de adicionar outro turno.');
      return;
    }

    final zones = ref.read(operationalZonesProvider).valueOrNull ?? [];
    final snapshot = _snapshotCurrentDraft(zones);

    setState(() {
      _confirmedShiftDrafts.add(snapshot);
      _errorMessage = null;
      _currentStep = 1; // Return to Step 2 (Turno) for the next shift
    });

    _resetForReturnShift();
  }

  // ── Submit ───────────────────────────────────────────────────

  String _computeHash(DeclareContractualPlanCommand cmd) {
    final payload = {
      'contract_id': cmd.contractId,
      'base_value_cents': cmd.contractualValueCents,
      'patterns': cmd.shiftPatterns
          .map((p) => {
                'days': p.daysOfWeek.map((d) => d.value).toList()..sort(),
                'arrival': p.arrivalTimeLocal,
                'departure': p.departureTimeLocal,
                'tz': p.timezone,
                'origin': p.originZoneId,
                'destination': p.destinationZoneId,
                'category': p.requiredVehicleCategory.toJson(),
              })
          .toList(),
    };
    return sha256.convert(utf8.encode(jsonEncode(payload))).toString();
  }

  ShiftPattern _draftToPattern(_ShiftDraftSnapshot d, int index) {
    final penalties = SLAPenalties.create(
      noShowPenaltyMultiplier: d.noShowMultiplier,
      delayToleranceMinutes: d.delayToleranceMinutes,
      delayPenaltyPerMinute: Money(d.delayPenaltyCentsPerMinute),
      downgradePenaltyFlat: Money(d.downgradePenaltyCents),
      noShowThresholdMinutes: d.noShowThresholdMinutes,
      earlyArrivalToleranceMinutes: d.earlyArrivalToleranceMinutes,
      dwellTimeMinutes: d.dwellTimeMinutes,
    );
    return ShiftPattern.create(
      index: index,
      daysOfWeek: d.selectedDays.map((v) => DayOfWeek.fromValue(v)).toList(),
      arrivalTimeLocal: _formatTime(d.arrivalTime),
      departureTimeLocal: _formatTime(d.departureTime),
      timezone: d.timezone,
      originZoneId: d.originZoneId,
      destinationZoneId: d.destinationZoneId,
      penalties: penalties,
      requiredVehicleCategory: d.requiredVehicleCategory,
    );
  }

  Future<void> _submit() async {
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
      final zones = ref.read(operationalZonesProvider).valueOrNull ?? [];
      // Snapshot the final (current) draft
      final finalSnapshot = _snapshotCurrentDraft(zones);
      final allDrafts = [..._confirmedShiftDrafts, finalSnapshot];

      // Build all ShiftPatterns with sequential indices
      final patterns = <ShiftPattern>[];
      for (var i = 0; i < allDrafts.length; i++) {
        patterns.add(_draftToPattern(allDrafts[i], i));
      }

      // Derive contractualValueCents from the first turn's base value
      // (all turns share the same contractual value in the command)
      final baseValueCents = allDrafts.first.baseValueCents;

      final planRepo = ref.read(planDeclarationRepositoryProvider);
      final existing = await planRepo.findByContract(
        widget.contractId,
        organizationId: organizationId,
      );
      final nextVersion = existing.isEmpty
          ? 1
          : existing.map((p) => p.planVersion).reduce((a, b) => a > b ? a : b) +
              1;

      var cmd = DeclareContractualPlanCommand(
        organizationId: organizationId,
        contractId: widget.contractId,
        declaredByUserId: operatorId,
        planVersion: nextVersion,
        originalFileHash: '',
        declaredAtUtc: DateTime.now().toUtc(),
        shiftPatterns: patterns,
        contractualValueCents: baseValueCents,
      );

      cmd = DeclareContractualPlanCommand(
        organizationId: cmd.organizationId,
        contractId: cmd.contractId,
        declaredByUserId: cmd.declaredByUserId,
        planVersion: cmd.planVersion,
        originalFileHash: _computeHash(cmd),
        declaredAtUtc: cmd.declaredAtUtc,
        shiftPatterns: cmd.shiftPatterns,
        contractualValueCents: cmd.contractualValueCents,
      );

      final handler = ref.read(declareContractualPlanHandlerProvider);
      await handler.handle(cmd);

      if (mounted) Navigator.of(context).pop(true);
    } on DomainException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Erro inesperado: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── UI Builders ──────────────────────────────────────────────

  Widget _buildStep1() {
    final zonesAsync = ref.watch(operationalZonesProvider);

    return zonesAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Erro ao carregar zonas operacionais: $e',
          style: const TextStyle(color: BusFlowColors.error),
        ),
      ),
      data: (zones) {
        final items = zones.map((zone) {
          final hasGeofence = zone.geofence != null;
          return DropdownMenuItem<String>(
            value: zone.id,
            child: Row(
              children: [
                Icon(
                  hasGeofence ? Icons.location_on : Icons.location_off,
                  size: 16,
                  color: hasGeofence ? BusFlowColors.onTime : BusFlowColors.warning,
                ),
                const SizedBox(width: 8),
                Text(zone.name),
              ],
            ),
          );
        }).toList();

        final originZone =
            zones.where((z) => z.id == _selectedOriginZoneId).firstOrNull;
        final destZone =
            zones.where((z) => z.id == _selectedDestinationZoneId).firstOrNull;
        final missingGeofence = [originZone, destZone]
            .where((z) => z != null && z.geofence == null)
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selecione as zonas operacionais (geofences) que delineiam esta rota B2B.',
              style: TextStyle(color: BusFlowColors.textSecondary),
            ),
            const SizedBox(height: 20),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Zona de Partida',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.business),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedOriginZoneId,
                  isExpanded: true,
                  items: items,
                  onChanged: (val) => setState(() => _selectedOriginZoneId = val),
                ),
              ),
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Zona de Chegada (Destino)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedDestinationZoneId,
                  isExpanded: true,
                  items: items,
                  onChanged: (val) =>
                      setState(() => _selectedDestinationZoneId = val),
                ),
              ),
            ),
            if (missingGeofence.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: BusFlowColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: BusFlowColors.warning.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 16, color: BusFlowColors.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${missingGeofence.map((z) => z!.name).join(', ')} não possui geofence '
                        'configurado — a engine de projeção não conseguirá validar chegada/partida automaticamente.',
                        style: const TextStyle(
                            fontSize: 12, color: BusFlowColors.warning),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildStep2() {
    const daysMap = {
      1: 'Seg', 2: 'Ter', 3: 'Qua', 4: 'Qui',
      5: 'Sex', 6: 'Sáb', 7: 'Dom',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _confirmedShiftDrafts.isEmpty
              ? 'Configure o padrão de recorrência: dias, horários, fuso e categoria de veículo exigida.'
              : 'Turno ${_confirmedShiftDrafts.length + 1} de ${_confirmedShiftDrafts.length + 1} — configure o turno de Retorno.',
          style: const TextStyle(color: BusFlowColors.textSecondary),
        ),
        const SizedBox(height: 20),

        // ── Dias da semana ────────────────────────────────────
        const Text('Dias da Semana', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: daysMap.entries.map((e) {
            final isSelected = _selectedDays.contains(e.key);
            return FilterChip(
              label: Text(e.value),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedDays.add(e.key);
                  } else {
                    _selectedDays.remove(e.key);
                  }
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 24),

        // ── Horários ──────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: BusFlowColors.border),
                ),
                leading: const Icon(Icons.flight_takeoff),
                title: const Text('Horário de Partida'),
                subtitle: Text(_departureTime != null
                    ? _formatTime(_departureTime!)
                    : 'Não definido'),
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: const TimeOfDay(hour: 6, minute: 0),
                  );
                  if (time != null) setState(() => _departureTime = time);
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: BusFlowColors.border),
                ),
                leading: const Icon(Icons.flight_land),
                title: const Text('Horário de Chegada'),
                subtitle: Text(_arrivalTime != null
                    ? _formatTime(_arrivalTime!)
                    : 'Não definido'),
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: const TimeOfDay(hour: 7, minute: 0),
                  );
                  if (time != null) setState(() => _arrivalTime = time);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ── Fuso Horário ──────────────────────────────────────
        DropdownButtonFormField<String>(
          value: _kBrTimezones.contains(_timezone) ? _timezone : _kBrTimezones.first,
          decoration: const InputDecoration(
            labelText: 'Fuso Horário *',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.schedule),
            helperText:
                'Os horários de chegada/partida serão interpretados neste fuso.',
          ),
          items: _kBrTimezones
              .map((tz) => DropdownMenuItem(value: tz, child: Text(tz)))
              .toList(),
          onChanged: (v) => setState(() => _timezone = v ?? _timezone),
        ),
        const SizedBox(height: 16),

        // ── Categoria de Veículo Exigida ──────────────────────
        DropdownButtonFormField<VehicleCategory>(
          value: _requiredVehicleCategory,
          decoration: const InputDecoration(
            labelText: 'Categoria de Veículo Exigida *',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.directions_bus),
            helperText:
                'Define a cláusula de downgrade — viagens realizadas com veículo inferior geram multa contratual.',
          ),
          items: VehicleCategory.values
              .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
              .toList(),
          onChanged: (v) =>
              setState(() => _requiredVehicleCategory = v ?? _requiredVehicleCategory),
        ),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cláusulas contratuais B2B. Configure os ofensores financeiros e janelas operacionais.',
          style: TextStyle(color: BusFlowColors.textSecondary),
        ),
        const SizedBox(height: 20),

        // Valor base (fora dos grupos SLA)
        TextField(
          controller: _baseValueController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Valor Base por Viagem (R\$)',
            prefixText: r'R$ ',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 28),

        // ── Grupo 1: Pontualidade ──────────────────────────────
        _SectionHeader(icon: Icons.schedule, label: 'Pontualidade e Janelas Operacionais'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _delayToleranceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tolerância de Atraso (min)',
                  suffixText: ' min',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _earlyArrivalToleranceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tolerância de Antecipação (min)',
                  suffixText: ' min',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _dwellTimeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tempo Mínimo de Permanência (min)',
                  suffixText: ' min',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // ── Grupo 2: Falhas Críticas ───────────────────────────
        _SectionHeader(
            icon: Icons.warning_amber_rounded,
            label: 'Falhas Críticas (Cláusulas de Penalidade)'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _noShowMultiplierController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Multiplicador No-Show',
                  suffixText: ' x',
                  border: OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: Tooltip(
                    message:
                        'Alavanca Financeira: penalidade aplicada ao valor base '
                        'da viagem em caso de No-Show.\n'
                        'Ex.: 1,5x = 150% do valor contratual cobrado do operador.',
                    child: Icon(Icons.help_outline, size: 16),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _noShowThresholdController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Teto para No-Show Automático (min)',
                  suffixText: ' min',
                  border: OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: Tooltip(
                    message:
                        'Atraso (em minutos) a partir do qual o sistema '
                        'classifica automaticamente a execução como No-Show. '
                        'Padrão de mercado: 60 min.',
                    child: Icon(Icons.help_outline, size: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // ── Grupo 3: Qualidade da Frota ────────────────────────
        _SectionHeader(icon: Icons.directions_bus, label: 'Qualidade da Frota'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _delayMinuteValueController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Multa por Minuto de Atraso',
                  prefixText: 'R\$ ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _downgradeValueController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Multa por Downgrade de Veículo',
                  prefixText: 'R\$ ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStep4() {
    final zonesAsync = ref.watch(operationalZonesProvider);
    final zones = zonesAsync.valueOrNull ?? [];

    // Combine confirmed drafts + current form as the final turn
    final allTurns = [
      ..._confirmedShiftDrafts,
      if (_selectedOriginZoneId != null &&
          _selectedDestinationZoneId != null &&
          _arrivalTime != null &&
          _departureTime != null)
        _snapshotCurrentDraft(zones),
    ];

    // Compute hash string for display (uses all patterns)
    String hashDisplay = '—';
    if (allTurns.isNotEmpty) {
      final draftHash = sha256
          .convert(utf8.encode(jsonEncode({
            'contract_id': widget.contractId,
            'patterns': allTurns
                .map((d) => {
                      'origin': d.originZoneId,
                      'destination': d.destinationZoneId,
                      'arrival': _formatTime(d.arrivalTime),
                      'departure': _formatTime(d.departureTime),
                      'tz': d.timezone,
                      'category': d.requiredVehicleCategory.toJson(),
                    })
                .toList(),
          })))
          .toString();
      hashDisplay = draftHash;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Revise todos os turnos antes de assinar. Após publicado, este plano não poderá ser alterado — uma nova versão precisará ser declarada.',
          style: TextStyle(color: BusFlowColors.textSecondary),
        ),
        const SizedBox(height: 16),

        // ── Turn cards ────────────────────────────────────────
        ...allTurns.asMap().entries.map((entry) {
          final i = entry.key;
          final d = entry.value;
          final label = allTurns.length == 1
              ? 'Turno Único'
              : i == 0
                  ? 'Turno ${i + 1} — Ida'
                  : 'Turno ${i + 1} — Retorno';

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              color: BusFlowColors.info.withValues(alpha: 0.10),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side:
                    const BorderSide(color: BusFlowColors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Turn header
                    Row(
                      children: [
                        const Icon(Icons.directions_bus,
                            size: 16, color: BusFlowColors.info),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: BusFlowColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Route
                    _ReviewRow(
                      icon: Icons.route,
                      label: 'Rota',
                      value:
                          '${d.originZoneName}  →  ${d.destinationZoneName}',
                    ),
                    // Schedule
                    _ReviewRow(
                      icon: Icons.calendar_today,
                      label: 'Dias',
                      value: _formatDays(d.selectedDays),
                    ),
                    _ReviewRow(
                      icon: Icons.schedule,
                      label: 'Horários',
                      value:
                          'Partida ${_formatTime(d.departureTime)}  ·  Chegada ${_formatTime(d.arrivalTime)}  ·  ${d.timezone}',
                    ),
                    _ReviewRow(
                      icon: Icons.directions_bus_outlined,
                      label: 'Categoria exigida',
                      value: d.requiredVehicleCategory.label,
                    ),
                    const Divider(height: 20, color: BusFlowColors.border),

                    // SLA
                    _ReviewRow(
                      icon: Icons.attach_money,
                      label: 'Valor base',
                      value: _formatCents(d.baseValueCents),
                    ),
                    _ReviewRow(
                      icon: Icons.timer,
                      label: 'Pontualidade',
                      value:
                          'Atraso: ${d.delayToleranceMinutes} min  ·  Antecipação: ${d.earlyArrivalToleranceMinutes} min  ·  Permanência mín: ${d.dwellTimeMinutes} min',
                    ),
                    _ReviewRow(
                      icon: Icons.warning_amber_rounded,
                      label: 'No-Show',
                      value:
                          '${d.noShowMultiplier.toStringAsFixed(1)}x valor base  ·  Teto: ${d.noShowThresholdMinutes} min',
                    ),
                    _ReviewRow(
                      icon: Icons.money_off,
                      label: 'Multas',
                      value:
                          '${_formatCents(d.delayPenaltyCentsPerMinute)}/min atraso  ·  Downgrade: ${_formatCents(d.downgradePenaltyCents)}',
                    ),
                  ],
                ),
              ),
            ),
          );
        }),

        const SizedBox(height: 8),

        // ── Hash ──────────────────────────────────────────────
        Tooltip(
          message: hashDisplay,
          child: Row(
            children: [
              const Icon(Icons.fingerprint, size: 14, color: BusFlowColors.textDisabled),
              const SizedBox(width: 6),
              Text(
                'SHA-256: ${hashDisplay.length > 16 ? '${hashDisplay.substring(0, 16)}…' : hashDisplay}',
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: BusFlowColors.textDisabled,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Imutabilidade ─────────────────────────────────────
        const Text(
          '⚠️ Após publicado, este Padrão de Turno não poderá ser modificado diretamente. Uma nova versão do plano precisará ser declarada.',
          style: TextStyle(
              color: BusFlowColors.warning, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 740),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24).copyWith(bottom: 0),
              child: Row(
                children: [
                  const Icon(Icons.playlist_add_check_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Configurar Padrão de Fretamento (B2B)',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          widget.contractName,
                          style: const TextStyle(
                            fontSize: 12,
                            color: BusFlowColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Show confirmed turns badge
                  if (_confirmedShiftDrafts.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: BusFlowColors.info.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: BusFlowColors.info.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        '${_confirmedShiftDrafts.length + 1} turnos',
                        style: const TextStyle(
                          fontSize: 11,
                          color: BusFlowColors.info,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(false),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            const Divider(height: 24),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: BusFlowColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: BusFlowColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: BusFlowColors.error, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                              color: BusFlowColors.error, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: Stepper(
                type: StepperType.horizontal,
                currentStep: _currentStep,
                onStepContinue: _onStepContinue,
                onStepCancel: _onStepCancel,
                controlsBuilder: (context, details) {
                  final isLastStep = _currentStep == 3;
                  final isStep3 = _currentStep == 2;
                  return Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed:
                              _isSubmitting ? null : details.onStepContinue,
                          icon: _isSubmitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white),
                                )
                              : Icon(isLastStep
                                  ? Icons.publish
                                  : Icons.arrow_forward),
                          label: Text(
                              isLastStep ? 'Publicar SLA B2B' : 'Continuar'),
                        ),
                        // "+ Adicionar Turno de Retorno" only on Step 3
                        if (isStep3)
                          OutlinedButton.icon(
                            onPressed: _isSubmitting ? null : _addReturnShift,
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('+ Adicionar Turno de Retorno'),
                          ),
                        TextButton(
                          onPressed:
                              _isSubmitting ? null : details.onStepCancel,
                          child: Text(
                              _currentStep == 0 ? 'Cancelar' : 'Voltar'),
                        ),
                      ],
                    ),
                  );
                },
                steps: [
                  Step(
                    title: const Text('Zonas Operacionais'),
                    content: _buildStep1(),
                    isActive: _currentStep >= 0,
                    state: _currentStep > 0
                        ? StepState.complete
                        : StepState.editing,
                  ),
                  Step(
                    title: const Text('Turno'),
                    content: _buildStep2(),
                    isActive: _currentStep >= 1,
                    state: _currentStep > 1
                        ? StepState.complete
                        : _currentStep == 1
                            ? StepState.editing
                            : StepState.indexed,
                  ),
                  Step(
                    title: const Text('Ofensores de Margem'),
                    content: _buildStep3(),
                    isActive: _currentStep >= 2,
                    state: _currentStep > 2
                        ? StepState.complete
                        : _currentStep == 2
                            ? StepState.editing
                            : StepState.indexed,
                  ),
                  Step(
                    title: const Text('Revisão'),
                    content: _buildStep4(),
                    isActive: _currentStep >= 3,
                    state: _currentStep == 3
                        ? StepState.editing
                        : StepState.indexed,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Support widgets ───────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: BusFlowColors.info),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: BusFlowColors.info,
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(child: Divider()),
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ReviewRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: BusFlowColors.textSecondary),
          const SizedBox(width: 6),
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: BusFlowColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                color: BusFlowColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
