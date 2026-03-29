import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/sla_audit/declare_contractual_plan_command.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/operational_zone.dart';
import 'package:veraprob/domain/sla_audit/shift_pattern.dart';
import 'package:veraprob/domain/sla_audit/sla_penalties.dart';
import 'package:veraprob/domain/sla_audit/vehicle_category.dart';
import 'package:veraprob/domain/sla_audit/week_cycle.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/contract_providers.dart';
import 'package:veraprob/state/providers/operational_zone_providers.dart';
import 'package:veraprob/state/providers/sla_providers.dart';
import 'package:veraprob/domain/sla_audit/sla_template.dart';
import 'package:veraprob/domain/sla_audit/smart_defaults.dart';
import 'package:veraprob/domain/sla_audit/transport_vertical.dart';
import 'package:veraprob/state/providers/sla_template_providers.dart';
import 'package:veraprob/application/sla_audit/sla_template_presets.dart';

import '../widgets/zone_type_ahead_field.dart';
import '../widgets/transport_vertical_chip.dart';

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
  final int gracePeriodMinutes;
  final WeekCycle weekCycle;

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
    required this.gracePeriodMinutes,
    required this.weekCycle,
  });
}

/// Dialog form for declaring a new B2B Plan for an existing contract.
///
/// Supports declaring multiple [ShiftPattern]s (e.g., round-trip) in a
/// single wizard session by accumulating confirmed turns via [_ShiftDraftSnapshot].
class DeclareContractPlanForm extends ConsumerStatefulWidget {
  final String contractId;
  final String contractName;
  final String contractorName;

  const DeclareContractPlanForm({
    super.key,
    required this.contractId,
    required this.contractName,
    required this.contractorName,
  });

  static Future<bool?> show(
    BuildContext context,
    WidgetRef ref, {
    required String contractId,
    required String contractName,
    String contractorName = '',
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DeclareContractPlanForm(
        contractId: contractId,
        contractName: contractName,
        contractorName: contractorName,
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

  /// Tracks the furthest step the user has successfully reached.
  /// Steps beyond this are shown as [StepState.disabled] and block forward taps.
  int _highestStepReached = 0;
  bool _isSubmitting = false;
  String? _errorMessage;

  // ── Round-trip: accumulator of confirmed turns ───────────────
  final List<_ShiftDraftSnapshot> _confirmedShiftDrafts = [];

  // ── Step 1: Zonas Operacionais ───────────────────────────────
  String? _selectedOriginZoneId;
  String? _selectedDestinationZoneId;
  OperationalZone? _selectedOriginZone;
  OperationalZone? _selectedDestinationZone;

  // ── Step 2: Padrão de Turno ──────────────────────────────────
  final Set<int> _selectedDays = {1, 2, 3, 4, 5}; // Seg-Sex
  TimeOfDay? _arrivalTime;
  TimeOfDay? _departureTime;
  String _timezone = 'America/Sao_Paulo';
  VehicleCategory _requiredVehicleCategory = VehicleCategory.conventional;
  WeekCycle _weekCycle = WeekCycle.everyWeek;

  // ── Step 3: SLA & Penalidades ────────────────────────────────
  final TextEditingController _baseValueController = TextEditingController();

  // Grupo 1 — Pontualidade e Janelas Operacionais
  final TextEditingController _delayToleranceController = TextEditingController(
    text: '15',
  );
  final TextEditingController _earlyArrivalToleranceController =
      TextEditingController(text: '5');
  final TextEditingController _dwellTimeController = TextEditingController(
    text: '3',
  );
  final TextEditingController _gracePeriodController = TextEditingController(
    text: '0',
  );

  // Grupo 2 — Falhas Críticas
  final TextEditingController _noShowMultiplierController =
      TextEditingController(text: '1,5');
  final TextEditingController _noShowThresholdController =
      TextEditingController(text: '60');

  // Grupo 3 — Qualidade da Frota
  final TextEditingController _delayMinuteValueController =
      TextEditingController(text: '0,50');
  final TextEditingController _downgradeValueController = TextEditingController(
    text: '50,00',
  );

  // ── Step 3 FocusNodes ────────────────────────────────────────
  final FocusNode _baseValueFocus = FocusNode();
  final FocusNode _delayToleranceFocus = FocusNode();
  final FocusNode _noShowMultiplierFocus = FocusNode();
  final FocusNode _delayMinuteValueFocus = FocusNode();
  final FocusNode _downgradeValueFocus = FocusNode();
  final FocusNode _earlyArrivalFocus = FocusNode();
  final FocusNode _dwellTimeFocus = FocusNode();
  final FocusNode _noShowThresholdFocus = FocusNode();
  final FocusNode _gracePeriodFocus = FocusNode();

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
    _gracePeriodController.addListener(_clearError);
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
    _gracePeriodController.dispose();
    _baseValueFocus.dispose();
    _delayToleranceFocus.dispose();
    _noShowMultiplierFocus.dispose();
    _delayMinuteValueFocus.dispose();
    _downgradeValueFocus.dispose();
    _earlyArrivalFocus.dispose();
    _dwellTimeFocus.dispose();
    _noShowThresholdFocus.dispose();
    _gracePeriodFocus.dispose();
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

  String _formatCents(int cents) => NumberFormat.currency(
    locale: 'pt_BR',
    symbol: 'R\$ ',
  ).format(cents / 100.0);

  String _formatDays(Set<int> days) {
    const map = {
      1: 'Seg',
      2: 'Ter',
      3: 'Qua',
      4: 'Qui',
      5: 'Sex',
      6: 'Sáb',
      7: 'Dom',
    };
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
      noShowThresholdMinutes:
          int.tryParse(_noShowThresholdController.text) ?? 60,
      delayPenaltyCentsPerMinute: _parseReaisToCents(
        _delayMinuteValueController.text,
      ),
      downgradePenaltyCents: _parseReaisToCents(_downgradeValueController.text),
      gracePeriodMinutes: int.tryParse(_gracePeriodController.text) ?? 0,
      weekCycle: _weekCycle,
    );
  }

  /// Resets Steps 2–3 fields for the next shift (e.g. return trip).
  /// Swaps origin/destination zones to pre-fill the reverse route.
  void _resetForReturnShift() {
    final swappedOrigin = _selectedDestinationZoneId;
    final swappedDest = _selectedOriginZoneId;
    final swappedOriginZone = _selectedDestinationZone;
    final swappedDestZone = _selectedOriginZone;
    setState(() {
      _selectedOriginZoneId = swappedOrigin;
      _selectedDestinationZoneId = swappedDest;
      _selectedOriginZone = swappedOriginZone;
      _selectedDestinationZone = swappedDestZone;
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
    _gracePeriodController.text = '0';
    _weekCycle = WeekCycle.everyWeek;
  }

  // ── Stepper Navigation ───────────────────────────────────────

  /// Validates Step 0 (Zonas). Returns an error message, or null if valid.
  String? _validateStep0() {
    if (_selectedOriginZoneId == null || _selectedDestinationZoneId == null) {
      return 'Selecione a Zona de Partida e a Zona de Chegada para continuar.';
    }
    if (_selectedOriginZoneId == _selectedDestinationZoneId) {
      return 'A Zona de Partida e Chegada devem ser diferentes.';
    }
    // ── GEOFENCE HARD BLOCK ─────────────────────────────────────
    // The engine is blind without coordinates + radius. Do NOT allow
    // advancing to the shift pattern step if any zone lacks a geofence.
    final zones = ref.read(operationalZonesProvider).valueOrNull ?? [];
    final originZone = zones
        .where((z) => z.id == _selectedOriginZoneId)
        .firstOrNull;
    final destZone = zones
        .where((z) => z.id == _selectedDestinationZoneId)
        .firstOrNull;
    final missingNames = [
      if (originZone?.geofence == null) originZone?.name ?? 'Zona de Partida',
      if (destZone?.geofence == null) destZone?.name ?? 'Zona de Chegada',
    ];
    if (missingNames.isNotEmpty) {
      return 'BLOQUEIO DE AUDITORIA: ${missingNames.join(' e ')} não possui '
          'geofence configurado (Latitude, Longitude e Raio). '
          'Acesse Zonas Operacionais → edite a zona → preencha os campos de '
          'Geofence antes de continuar.';
    }
    return null;
  }

  /// Validates Step 1 (Turno). Returns an error message, or null if valid.
  String? _validateStep1() {
    if (_selectedDays.isEmpty) {
      return 'Selecione ao menos um dia da semana para o turno.';
    }
    if (_arrivalTime == null || _departureTime == null) {
      return 'Defina os horários de Chegada e Partida do turno.';
    }
    return null;
  }

  /// Validates Step 2 (SLA / Ofensores de Margem). Returns an error message, or null if valid.
  String? _validateStep2() {
    final baseVal = _parseReaisToCents(_baseValueController.text);
    if (baseVal <= 0) {
      return 'O valor base da viagem contratada não pode ser zero.';
    }
    return null;
  }

  void _onStepContinue() {
    String? error;
    if (_currentStep == 0) {
      error = _validateStep0();
    } else if (_currentStep == 1) {
      error = _validateStep1();
    } else if (_currentStep == 2) {
      error = _validateStep2();
    }

    if (error != null) {
      setState(() => _errorMessage = error);
      return;
    }

    setState(() {
      _errorMessage = null;
      if (_currentStep < 3) {
        _currentStep++;
        if (_currentStep > _highestStepReached) {
          _highestStepReached = _currentStep;
        }
      } else {
        _submit();
      }
    });
  }

  /// Handles tapping a step indicator directly.
  ///
  /// Back navigation is always allowed. Forward navigation requires all
  /// intermediate steps to pass validation. Steps beyond [_highestStepReached]
  /// are locked until the user progresses linearly.
  void _onStepTapped(int step) {
    if (step == _currentStep) return;

    // Back navigation — always allowed.
    if (step < _currentStep) {
      setState(() {
        _errorMessage = null;
        _currentStep = step;
      });
      return;
    }

    // Forward skip — only to steps already reached.
    if (step > _highestStepReached) {
      // Validate intermediate steps sequentially up to the target.
      for (var i = _currentStep; i < step; i++) {
        String? error;
        if (i == 0) {
          error = _validateStep0();
        } else if (i == 1) {
          error = _validateStep1();
        } else if (i == 2) {
          error = _validateStep2();
        }
        if (error != null) {
          setState(() => _errorMessage = error);
          return;
        }
      }
      // All intermediate steps passed — allow and mark highest reached.
      setState(() {
        _errorMessage = null;
        _currentStep = step;
        if (step > _highestStepReached) _highestStepReached = step;
      });
      return;
    }

    // Target is within already-reached range — jump freely.
    setState(() {
      _errorMessage = null;
      _currentStep = step;
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
      setState(
        () => _errorMessage =
            'O valor base da viagem contratada não pode ser zero antes de adicionar outro turno.',
      );
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
          .map(
            (p) => {
              'days': p.daysOfWeek.map((d) => d.value).toList()..sort(),
              'arrival': p.arrivalTimeLocal,
              'departure': p.departureTimeLocal,
              'tz': p.timezone,
              'origin': p.originZoneId,
              'destination': p.destinationZoneId,
              'category': p.requiredVehicleCategory.toJson(),
            },
          )
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
      gracePeriodMinutes: d.gracePeriodMinutes,
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
      weekCycle: d.weekCycle,
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
          style: const TextStyle(color: VeraProbColors.error),
        ),
      ),
      data: (zones) {
        // F3: Sort zones — contractor's own zones appear first
        final contractorZones = zones
            .where(
              (z) =>
                  z.contractorLabel == widget.contractorName &&
                  widget.contractorName.isNotEmpty,
            )
            .toList();
        final otherZones = zones
            .where(
              (z) =>
                  z.contractorLabel != widget.contractorName ||
                  widget.contractorName.isEmpty,
            )
            .toList();
        final sortedZones = [...contractorZones, ...otherZones];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selecione as zonas operacionais (geofences) que delineiam esta rota B2B.',
              style: TextStyle(color: VeraProbColors.textSecondary),
            ),
            const SizedBox(height: VeraProbSpacing.md),
            ZoneTypeAheadField(
              key: ValueKey('origin_$_selectedOriginZoneId'),
              label: 'Zona de Partida',
              prefixIcon: Icons.business,
              zones: sortedZones,
              selectedZone: _selectedOriginZone,
              contractorName: widget.contractorName,
              onInvalidateZones: () =>
                  ref.refresh(operationalZonesProvider.future),
              onChanged: (zone) => setState(() {
                _selectedOriginZone = zone;
                _selectedOriginZoneId = zone?.id;
              }),
              onGeofenceConfigured: (zone) => setState(() {
                _selectedOriginZone = zone;
              }),
            ),
            Center(
              child: IconButton(
                icon: const Icon(
                  Icons.swap_vert,
                  color: VeraProbColors.primary,
                ),
                tooltip: 'Inverter Origem/Destino',
                onPressed: () {
                  setState(() {
                    final tmpZone = _selectedOriginZone;
                    _selectedOriginZone = _selectedDestinationZone;
                    _selectedDestinationZone = tmpZone;

                    final tmpId = _selectedOriginZoneId;
                    _selectedOriginZoneId = _selectedDestinationZoneId;
                    _selectedDestinationZoneId = tmpId;
                  });
                },
              ),
            ),
            ZoneTypeAheadField(
              key: ValueKey('destination_$_selectedDestinationZoneId'),
              label: 'Zona de Chegada (Destino)',
              prefixIcon: Icons.location_on,
              zones: sortedZones,
              selectedZone: _selectedDestinationZone,
              contractorName: widget.contractorName,
              onInvalidateZones: () =>
                  ref.refresh(operationalZonesProvider.future),
              onChanged: (zone) => setState(() {
                _selectedDestinationZone = zone;
                _selectedDestinationZoneId = zone?.id;
              }),
              onGeofenceConfigured: (zone) => setState(() {
                _selectedDestinationZone = zone;
              }),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStep2() {
    const daysMap = {
      1: 'Seg',
      2: 'Ter',
      3: 'Qua',
      4: 'Qui',
      5: 'Sex',
      6: 'Sáb',
      7: 'Dom',
    };

    final originName =
        _selectedOriginZone?.name ?? _selectedOriginZoneId ?? '—';
    final destName =
        _selectedDestinationZone?.name ?? _selectedDestinationZoneId ?? '—';
    // For return shifts, display the current turn's direction (zones were swapped).
    final turnIndex = _confirmedShiftDrafts.length;
    final isReturnShift = turnIndex > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _confirmedShiftDrafts.isEmpty
              ? 'Configure o padrão de recorrência: dias, horários, fuso e categoria de veículo exigida.'
              : 'Turno ${_confirmedShiftDrafts.length + 1} de ${_confirmedShiftDrafts.length + 1} — configure o turno de Retorno.',
          style: const TextStyle(color: VeraProbColors.textSecondary),
        ),
        const SizedBox(height: 12),

        // ── Origem → Destino context banner ──────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: VeraProbColors.info.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: VeraProbColors.info.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            children: [
              if (isReturnShift) ...[
                Text(
                  'Turno de Retorno ${turnIndex + 1}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: VeraProbColors.info,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  '·',
                  style: TextStyle(color: VeraProbColors.textDisabled),
                ),
                const SizedBox(width: 10),
              ],
              const Icon(
                Icons.business,
                size: 14,
                color: VeraProbColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  originName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: VeraProbColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.arrow_forward,
                  size: 14,
                  color: VeraProbColors.info,
                ),
              ),
              const Icon(
                Icons.location_on,
                size: 14,
                color: VeraProbColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  destName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: VeraProbColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Dias da semana ────────────────────────────────────
        const Text(
          'Dias da Semana',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
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
                  side: const BorderSide(color: VeraProbColors.border),
                ),
                leading: const Icon(Icons.flight_takeoff),
                title: const Text('Horário de Partida'),
                subtitle: Text(
                  _departureTime != null
                      ? _formatTime(_departureTime!)
                      : 'Não definido',
                ),
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
                  side: const BorderSide(color: VeraProbColors.border),
                ),
                leading: const Icon(Icons.flight_land),
                title: const Text('Horário de Chegada'),
                subtitle: Text(
                  _arrivalTime != null
                      ? _formatTime(_arrivalTime!)
                      : 'Não definido',
                ),
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
          initialValue: _kBrTimezones.contains(_timezone)
              ? _timezone
              : _kBrTimezones.first,
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
          initialValue: _requiredVehicleCategory,
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
          onChanged: (v) => setState(
            () => _requiredVehicleCategory = v ?? _requiredVehicleCategory,
          ),
        ),
        const SizedBox(height: 16),

        // ── Ciclo de Recorrência (WeekCycle) ──────────────────
        DropdownButtonFormField<WeekCycle>(
          initialValue: _weekCycle,
          decoration: const InputDecoration(
            labelText: 'Ciclo de Recorrência *',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.repeat),
            helperText:
                'Define se o turno roda toda semana ou em semanas específicas do ciclo industrial.',
          ),
          items: [
            const DropdownMenuItem(
              value: WeekCycle.everyWeek,
              child: Text('Toda Semana'),
            ),
            const DropdownMenuItem(
              value: WeekCycle.weekA,
              child: Text('Semana A (1/4)'),
            ),
            const DropdownMenuItem(
              value: WeekCycle.weekB,
              child: Text('Semana B (2/4)'),
            ),
            const DropdownMenuItem(
              value: WeekCycle.weekC,
              child: Text('Semana C (3/4)'),
            ),
            const DropdownMenuItem(
              value: WeekCycle.weekD,
              child: Text('Semana D (4/4)'),
            ),
          ],
          onChanged: (v) => setState(() => _weekCycle = v ?? _weekCycle),
        ),
      ],
    );
  }

  void _applyPenaltiesFromTemplate(SLAPenalties p) {
    setState(() {
      _baseValueController.text = (p.baseTripValue.cents / 100.0)
          .toStringAsFixed(2)
          .replaceAll('.', ',');
      _noShowMultiplierController.text = p.noShowPenaltyMultiplier
          .toStringAsFixed(1)
          .replaceAll('.', ',');
      _delayToleranceController.text = p.delayToleranceMinutes.toString();
      _delayMinuteValueController.text = (p.delayPenaltyPerMinute.cents / 100.0)
          .toStringAsFixed(2)
          .replaceAll('.', ',');
      _downgradeValueController.text = (p.downgradePenaltyFlat.cents / 100.0)
          .toStringAsFixed(2)
          .replaceAll('.', ',');
      _noShowThresholdController.text = p.noShowThresholdMinutes.toString();
      _earlyArrivalToleranceController.text = p.earlyArrivalToleranceMinutes
          .toString();
      _dwellTimeController.text = p.dwellTimeMinutes.toString();
      _gracePeriodController.text = p.gracePeriodMinutes.toString();
    });
  }

  Future<void> _saveCurrentAsTemplate() async {
    final orgId = ref.read(currentOrganizationIdProvider);
    if (orgId == null) return;

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Salvar como Modelo'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nome do Modelo',
              hintText: 'Ex: Fretamento Interurbano',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    );

    if (name == null || name.isEmpty) return;

    try {
      final noShowMult =
          double.tryParse(
            _noShowMultiplierController.text.replaceAll(',', '.'),
          ) ??
          1.5;
      final delayPerMin =
          ((double.tryParse(
                        _delayMinuteValueController.text.replaceAll(',', '.'),
                      ) ??
                      0.5) *
                  100)
              .round();
      final downgrade =
          ((double.tryParse(
                        _downgradeValueController.text.replaceAll(',', '.'),
                      ) ??
                      50) *
                  100)
              .round();

      final penalties = SLAPenalties.create(
        noShowPenaltyMultiplier: noShowMult,
        delayToleranceMinutes:
            int.tryParse(_delayToleranceController.text) ?? 15,
        delayPenaltyPerMinute: Money(delayPerMin),
        downgradePenaltyFlat: Money(downgrade),
        noShowThresholdMinutes:
            int.tryParse(_noShowThresholdController.text) ?? 60,
        earlyArrivalToleranceMinutes:
            int.tryParse(_earlyArrivalToleranceController.text) ?? 5,
        dwellTimeMinutes: int.tryParse(_dwellTimeController.text) ?? 3,
        gracePeriodMinutes: int.tryParse(_gracePeriodController.text) ?? 0,
      );

      await ref
          .read(saveSlaTemplateHandlerProvider)
          .handle(organizationId: orgId, name: name, penalties: penalties);

      ref.invalidate(slaTemplatesProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Modelo "$name" salvo.'),
            backgroundColor: VeraProbColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao salvar modelo: $e'),
            backgroundColor: VeraProbColors.error,
          ),
        );
      }
    }
  }

  void _showTemplatePicker(AsyncValue<List<SlaTemplate>> allTemplatesAsync) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxHeight: 500),
      builder: (ctx) => allTemplatesAsync.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Erro ao carregar modelos: $e',
            style: const TextStyle(color: VeraProbColors.error),
          ),
        ),
        data: (templates) {
          if (templates.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Nenhum modelo disponível'),
              ),
            );
          }

          final presets = templates
              .where((t) => SlaTemplatePresets.isPreset(t.id))
              .toList();
          final orgTemplates = templates
              .where((t) => !SlaTemplatePresets.isPreset(t.id))
              .toList();

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (presets.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'MODELOS DO SISTEMA',
                    style: VeraProbTypography.badge.copyWith(
                      color: VeraProbColors.textSecondary,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                ...presets.map(
                  (t) => _TemplateTile(
                    template: t,
                    onTap: () {
                      _applyPenaltiesFromTemplate(t.penalties);
                      Navigator.of(ctx).pop();
                    },
                  ),
                ),
              ],
              if (orgTemplates.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'MEUS MODELOS',
                    style: VeraProbTypography.badge.copyWith(
                      color: VeraProbColors.textSecondary,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                ...orgTemplates.map(
                  (t) => _TemplateTile(
                    template: t,
                    onTap: () {
                      _applyPenaltiesFromTemplate(t.penalties);
                      Navigator.of(ctx).pop();
                    },
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildStep3() {
    final allTemplatesAsync = ref.watch(allTemplatesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Acordo de penalidades e janelas operacionais para garantir o nível de serviço.',
          style: TextStyle(color: VeraProbColors.textSecondary),
        ),
        const SizedBox(height: VeraProbSpacing.md),

        // ── Smart Defaults: Vertical dropdown ──────────────────────
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<TransportVertical>(
                decoration: const InputDecoration(
                  labelText: 'Vertical de Transporte',
                  prefixIcon: Icon(Icons.category_outlined, size: 20),
                  isDense: true,
                ),
                items: TransportVertical.values
                    .map(
                      (v) => DropdownMenuItem(value: v, child: Text(v.label)),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null || v == TransportVertical.custom) {
                    setState(() => _baseValueController.text = '');
                  } else {
                    _applyPenaltiesFromTemplate(SmartDefaults.defaultsFor(v));
                  }
                },
              ),
            ),
            // ── Load from Template (grouped: System + Org) ──────────
            OutlinedButton.icon(
              icon: const Icon(Icons.style, size: 16),
              label: const Text('Aplicar Modelo'),
              onPressed: () => _showTemplatePicker(allTemplatesAsync),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.save_outlined, size: 16),
              label: const Text('Salvar como Modelo'),
              onPressed: _saveCurrentAsTemplate,
            ),
          ],
        ),
        const SizedBox(height: VeraProbSpacing.md),

        // Valor base (fora dos grupos SLA)
        TextField(
          controller: _baseValueController,
          focusNode: _baseValueFocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Valor Base por Viagem (R\$)',
            prefixText: r'R$ ',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) =>
              FocusScope.of(context).requestFocus(_delayToleranceFocus),
        ),
        const SizedBox(height: VeraProbSpacing.lg),

        // ── Grupo 1: Pontualidade ──────────────────────────────
        const _SectionHeader(
          icon: Icons.schedule,
          label: 'Pontualidade e Janelas Operacionais',
        ),
        const SizedBox(height: VeraProbSpacing.sm),
        TextField(
          controller: _delayToleranceController,
          focusNode: _delayToleranceFocus,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Tolerância de Atraso (min)',
            suffixText: ' min',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (_) =>
              FocusScope.of(context).requestFocus(_gracePeriodFocus),
        ),
        const SizedBox(height: VeraProbSpacing.md),
        TextField(
          controller: _gracePeriodController,
          focusNode: _gracePeriodFocus,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Carência Pré-Avaliação (min)',
            suffixText: ' min',
            border: OutlineInputBorder(),
            isDense: true,
            helperText:
                'Janela de espera após o horário previsto antes de iniciar checagem.',
          ),
          onSubmitted: (_) =>
              FocusScope.of(context).requestFocus(_noShowMultiplierFocus),
        ),
        const SizedBox(height: VeraProbSpacing.lg),

        // ── Grupo 2: Falhas Críticas ───────────────────────────
        const _SectionHeader(
          icon: Icons.warning_amber_rounded,
          label: 'Falhas Críticas (Cláusulas de Penalidade)',
        ),
        const SizedBox(height: VeraProbSpacing.sm),
        TextField(
          controller: _noShowMultiplierController,
          focusNode: _noShowMultiplierFocus,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
          onSubmitted: (_) =>
              FocusScope.of(context).requestFocus(_delayMinuteValueFocus),
        ),
        const SizedBox(height: VeraProbSpacing.lg),

        // ── Grupo 3: Qualidade da Frota ────────────────────────
        const _SectionHeader(
          icon: Icons.directions_bus,
          label: 'Qualidade da Frota',
        ),
        const SizedBox(height: VeraProbSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _delayMinuteValueController,
                focusNode: _delayMinuteValueFocus,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Multa por Minuto de Atraso',
                  prefixText: 'R\$ ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) =>
                    FocusScope.of(context).requestFocus(_downgradeValueFocus),
              ),
            ),
            const SizedBox(width: VeraProbSpacing.sm),
            Expanded(
              child: TextField(
                controller: _downgradeValueController,
                focusNode: _downgradeValueFocus,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Multa por Downgrade de Veículo',
                  prefixText: 'R\$ ',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _onStepContinue(),
              ),
            ),
          ],
        ),
        const SizedBox(height: VeraProbSpacing.md),

        // F5 — ExpansionTile: Opções Avançadas
        ExpansionTile(
          leading: const Icon(Icons.tune),
          title: const Text('Opções Avançadas'),
          initiallyExpanded: false,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: VeraProbSpacing.md,
                right: VeraProbSpacing.md,
                bottom: VeraProbSpacing.md,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _earlyArrivalToleranceController,
                          focusNode: _earlyArrivalFocus,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Tolerância de Antecipação (min)',
                            suffixText: ' min',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => FocusScope.of(
                            context,
                          ).requestFocus(_dwellTimeFocus),
                        ),
                      ),
                      const SizedBox(width: VeraProbSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: _dwellTimeController,
                          focusNode: _dwellTimeFocus,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Tempo Mínimo de Permanência (min)',
                            suffixText: ' min',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => FocusScope.of(
                            context,
                          ).requestFocus(_noShowThresholdFocus),
                        ),
                      ),
                      const SizedBox(width: VeraProbSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: _noShowThresholdController,
                          focusNode: _noShowThresholdFocus,
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
                ],
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
          .convert(
            utf8.encode(
              jsonEncode({
                'contract_id': widget.contractId,
                'patterns': allTurns
                    .map(
                      (d) => {
                        'origin': d.originZoneId,
                        'destination': d.destinationZoneId,
                        'arrival': _formatTime(d.arrivalTime),
                        'departure': _formatTime(d.departureTime),
                        'tz': d.timezone,
                        'category': d.requiredVehicleCategory.toJson(),
                      },
                    )
                    .toList(),
              }),
            ),
          )
          .toString();
      hashDisplay = draftHash;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Resumo de exposição financeira e revisão detalhada dos turnos antes da publicação.',
          style: TextStyle(color: VeraProbColors.textSecondary),
        ),
        const SizedBox(height: 16),

        _buildRiskSummary(allTurns),

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
              color: VeraProbColors.info.withValues(alpha: 0.10),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: VeraProbColors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Turn header
                    Row(
                      children: [
                        const Icon(
                          Icons.directions_bus,
                          size: 16,
                          color: VeraProbColors.info,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: VeraProbColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Route
                    _ReviewRow(
                      icon: Icons.route,
                      label: 'Rota',
                      value: '${d.originZoneName}  →  ${d.destinationZoneName}',
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
                    const Divider(height: 20, color: VeraProbColors.border),

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
                          'Carência: ${d.gracePeriodMinutes} min  ·  Atraso: ${d.delayToleranceMinutes} min  ·  Antecipação: ${d.earlyArrivalToleranceMinutes} min  ·  Permanência mín: ${d.dwellTimeMinutes} min',
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
              const Icon(
                Icons.fingerprint,
                size: 14,
                color: VeraProbColors.textDisabled,
              ),
              const SizedBox(width: 6),
              Text(
                'SHA-256: ${hashDisplay.length > 16 ? '${hashDisplay.substring(0, 16)}…' : hashDisplay}',
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: VeraProbColors.textDisabled,
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
            color: VeraProbColors.warning,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildRiskSummary(List<_ShiftDraftSnapshot> allTurns) {
    if (allTurns.isEmpty) return const SizedBox.shrink();

    // ── Contract access (for financialCeiling) ────────────────
    final contractDetailAsync = ref.watch(
      contractDetailProvider(widget.contractId),
    );
    final contract = contractDetailAsync.valueOrNull?.summary;
    final financialCeilingCents = contract?.financialCeilingCents;

    // ── Pre-calculate totals ──────────────────────────────────
    int totalProtectedRevenueCents = 0;
    int totalMaxNoShowExposureCents = 0;
    int absoluteMaxPenaltyPerTripCents = 0;

    for (final d in allTurns) {
      // 4.33 weeks/month on avg; cyclic turns run only 1 week every 4.
      final multiplier = d.weekCycle == WeekCycle.everyWeek ? 4.33 : 1.083;
      final tripsPerMonth = d.selectedDays.length * multiplier;

      final revenue = (d.baseValueCents * tripsPerMonth).round();
      final noShowExposure =
          (d.baseValueCents * d.noShowMultiplier * tripsPerMonth).round();

      // Trip ceiling: max between full no-show or max delay pen before no-show conversion
      final noShowPenalty = (d.baseValueCents * d.noShowMultiplier).round();
      final delayPenaltyCeiling =
          d.delayPenaltyCentsPerMinute * d.noShowThresholdMinutes;
      final maxTripPenalty = noShowPenalty > delayPenaltyCeiling
          ? noShowPenalty
          : delayPenaltyCeiling;

      totalProtectedRevenueCents += revenue;
      totalMaxNoShowExposureCents += noShowExposure;
      if (maxTripPenalty > absoluteMaxPenaltyPerTripCents) {
        absoluteMaxPenaltyPerTripCents = maxTripPenalty;
      }
    }

    double? relativeRisk;
    if (financialCeilingCents != null && financialCeilingCents > 0) {
      relativeRisk =
          (totalMaxNoShowExposureCents / financialCeilingCents) * 100;
    }

    final hasBaseTripValue = allTurns.any((d) => d.baseValueCents > 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!hasBaseTripValue)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: VeraProbColors.warning,
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Configure o Valor Base por Viagem no Step 3 para habilitar os KPIs financeiros.',
                    style: TextStyle(
                      fontSize: 12,
                      color: VeraProbColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width:
                  (MediaQuery.sizeOf(context).width - 80) /
                  (MediaQuery.sizeOf(context).width < 600 ? 1 : 2),
              child: _KpiCard(
                icon: Icons.shield_outlined,
                label: 'Receita Protegida',
                value: _formatCents(totalProtectedRevenueCents),
                period: '/mês',
                tooltip:
                    'Soma dos valores contratuais por viagem × volume mensal projetado.',
              ),
            ),
            SizedBox(
              width:
                  (MediaQuery.sizeOf(context).width - 80) /
                  (MediaQuery.sizeOf(context).width < 600 ? 1 : 2),
              child: _KpiCard(
                icon: Icons.warning_amber_rounded,
                label: 'Exposição No-Show',
                value: _formatCents(totalMaxNoShowExposureCents),
                period: '/mês',
                tooltip:
                    'Risco máximo em caso de 100% de falha No-Show em todos os turnos.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width:
                  (MediaQuery.sizeOf(context).width - 80) /
                  (MediaQuery.sizeOf(context).width < 600 ? 1 : 2),
              child: _KpiCard(
                icon: Icons.money_off,
                label: 'Penalidade Máx.',
                value: _formatCents(absoluteMaxPenaltyPerTripCents),
                period: '/viagem',
                tooltip:
                    'Maior penalidade possível em um único evento (No-Show ou Atraso Crítico).',
              ),
            ),
            if (relativeRisk != null) ...[
              SizedBox(
                width:
                    (MediaQuery.sizeOf(context).width - 80) /
                    (MediaQuery.sizeOf(context).width < 600 ? 1 : 2),
                child: _KpiCard(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Risco Relativo',
                  value: '${relativeRisk.toStringAsFixed(1)}%',
                  period: 'do teto',
                  tooltip:
                      'Percentual do Teto Financeiro ocupado pela exposição máxima de No-Show mensal.',
                ),
              ),
            ] else ...[
              SizedBox(
                width:
                    (MediaQuery.sizeOf(context).width - 80) /
                    (MediaQuery.sizeOf(context).width < 600 ? 1 : 2),
                child: const _KpiCard(
                  icon: Icons.lock_outline,
                  label: 'Risco Relativo',
                  value: '—',
                  tooltip:
                      'Configure o Teto Financeiro no contrato para habilitar este indicador.',
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        const Divider(height: 32, color: VeraProbColors.border),
      ],
    );
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (MediaQuery.sizeOf(context).width * 0.94).clamp(
            360.0,
            860.0,
          ),
          maxHeight: (MediaQuery.sizeOf(context).height * 0.9).clamp(
            500.0,
            740.0,
          ),
        ),
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
                            color: VeraProbColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Show confirmed turns badge
                  if (_confirmedShiftDrafts.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: VeraProbColors.info.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: VeraProbColors.info.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        '${_confirmedShiftDrafts.length + 1} turnos',
                        style: const TextStyle(
                          fontSize: 11,
                          color: VeraProbColors.info,
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
                    color: VeraProbColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: VeraProbColors.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: VeraProbColors.error,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: VeraProbColors.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: Stepper(
                type: MediaQuery.sizeOf(context).width < 720
                    ? StepperType.vertical
                    : StepperType.horizontal,
                currentStep: _currentStep,
                onStepContinue: _onStepContinue,
                onStepCancel: _onStepCancel,
                onStepTapped: _onStepTapped,
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
                          onPressed: _isSubmitting
                              ? null
                              : details.onStepContinue,
                          icon: _isSubmitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  isLastStep
                                      ? Icons.publish
                                      : Icons.arrow_forward,
                                ),
                          label: Text(
                            isLastStep ? 'Publicar SLA B2B' : 'Continuar',
                          ),
                        ),
                        // "+ Adicionar Turno de Retorno" only on Step 3
                        if (isStep3)
                          OutlinedButton.icon(
                            onPressed: _isSubmitting ? null : _addReturnShift,
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('+ Adicionar Turno de Retorno'),
                          ),
                        TextButton(
                          onPressed: _isSubmitting
                              ? null
                              : details.onStepCancel,
                          child: Text(
                            _currentStep == 0 ? 'Cancelar' : 'Voltar',
                          ),
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
                        : _highestStepReached >= 1
                        ? StepState.indexed
                        : StepState.disabled,
                  ),
                  Step(
                    title: const Text('Acordo de Penalidades'),
                    content: _buildStep3(),
                    isActive: _currentStep >= 2,
                    state: _currentStep > 2
                        ? StepState.complete
                        : _currentStep == 2
                        ? StepState.editing
                        : _highestStepReached >= 2
                        ? StepState.indexed
                        : StepState.disabled,
                  ),
                  Step(
                    title: const Text('Exposição de Risco'),
                    content: _buildStep4(),
                    isActive: _currentStep >= 3,
                    state: _currentStep == 3
                        ? StepState.editing
                        : _highestStepReached >= 3
                        ? StepState.indexed
                        : StepState.disabled,
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

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? period;
  final String? tooltip;

  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
    this.period,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: VeraProbColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: VeraProbColors.textSecondary,
                ),
              ),
              if (tooltip != null) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: tooltip!,
                  child: const Icon(
                    Icons.help_outline,
                    size: 12,
                    color: VeraProbColors.textDisabled,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: VeraProbColors.textPrimary,
                ),
              ),
              if (period != null) ...[
                const SizedBox(width: 4),
                Text(
                  period!,
                  style: const TextStyle(
                    fontSize: 10,
                    color: VeraProbColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TemplateTile extends StatelessWidget {
  final SlaTemplate template;
  final VoidCallback onTap;

  const _TemplateTile({required this.template, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: template.vertical != null
          ? TransportVerticalChip(vertical: template.vertical!)
          : null,
      title: Text(template.name),
      subtitle: Text(
        _penaltySummary(template.penalties),
        style: VeraProbTypography.caption,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: SlaTemplatePresets.isPreset(template.id)
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: VeraProbColors.secondary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'SISTEMA',
                style: VeraProbTypography.badge.copyWith(
                  color: VeraProbColors.secondary,
                  fontSize: 9,
                ),
              ),
            )
          : null,
      onTap: onTap,
    );
  }

  String _penaltySummary(SLAPenalties p) {
    final delay = (p.delayPenaltyPerMinute.cents / 100.0).toStringAsFixed(2);
    return '${p.noShowPenaltyMultiplier}x no-show · '
        '${p.delayToleranceMinutes}min tol · '
        'R\$ $delay/min atraso';
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: VeraProbColors.info),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: VeraProbColors.info,
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
    final isNarrow = MediaQuery.sizeOf(context).width < 480;
    final content = [
      SizedBox(
        width: isNarrow ? null : 130,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: VeraProbColors.textSecondary,
          ),
        ),
      ),
      if (isNarrow) const SizedBox(height: 2),
      Expanded(
        flex: isNarrow ? 0 : 1,
        child: Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            color: VeraProbColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14, color: VeraProbColors.textSecondary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: isNarrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: content,
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: content,
                  ),
          ),
        ],
      ),
    );
  }
}
