import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/operational_zone_providers.dart';
import 'package:veraprob/state/providers/sla_providers.dart';
import 'package:veraprob/state/notifiers/contract_command_notifier.dart';

import 'package:veraprob/features/admin/presentation/screens/widgets/declare_plan/declare_plan_dialog_header.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/declare_plan/declare_plan_ui_utils.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/declare_plan/declare_plan_zones_step.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/declare_plan/shift_draft_snapshot.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/declare_plan/shift_pattern_step.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/declare_plan/_sla_penalties_step.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/declare_plan/review_step.dart';

/// Dialog form for declaring a new B2B Plan for an existing contract.
///
/// **INV-33 (Idempotency):** Integrated with [ContractCommandNotifier] to
/// handle stable keys and intention-based recycling (onFormChanged).
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
  int _highestStepReached = 0;
  bool _isSubmitting = false;
  String? _errorMessage;

  // ── Round-trip: accumulator of confirmed turns ───────────────
  final List<ShiftDraftSnapshot> _confirmedShiftDrafts = [];

  // ── Step 1: Zonas Operacionais ───────────────────────────────
  String? _selectedOriginZoneId;
  String? _selectedDestinationZoneId;
  OperationalZoneView? _selectedOriginZone;
  OperationalZoneView? _selectedDestinationZone;

  // ── Step 2: Padrão de Turno ──────────────────────────────────
  final Set<int> _selectedDays = {1, 2, 3, 4, 5}; // Seg-Sex
  TimeOfDay? _arrivalTime;
  TimeOfDay? _departureTime;
  String _timezone = 'America/Sao_Paulo';
  VehicleCategory _requiredVehicleCategory = VehicleCategory.conventional;
  WeekCycle _weekCycle = WeekCycle.everyWeek;

  // ── Step 3: SLA & Penalidades ────────────────────────────────
  final TextEditingController _baseValueController = TextEditingController();
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
  final TextEditingController _noShowMultiplierController =
      TextEditingController(text: '1,5');
  final TextEditingController _noShowThresholdController =
      TextEditingController(text: '60');
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
    // [INV-33] Data change triggers new idempotency key if in error state
    _baseValueController.addListener(_onDataChanged);
    _delayToleranceController.addListener(_onDataChanged);
    _earlyArrivalToleranceController.addListener(_onDataChanged);
    _dwellTimeController.addListener(_onDataChanged);
    _noShowMultiplierController.addListener(_onDataChanged);
    _noShowThresholdController.addListener(_onDataChanged);
    _delayMinuteValueController.addListener(_onDataChanged);
    _downgradeValueController.addListener(_onDataChanged);
    _gracePeriodController.addListener(_onDataChanged);
  }

  void _onDataChanged() {
    _clearError();
    ref
        .read(contractCommandNotifierProvider(widget.contractId).notifier)
        .onFormChanged();
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

  // ── Snapshot helpers ─────────────────────────────────────────

  String _zoneName(String? id, List<OperationalZoneView> zones) {
    if (id == null) return '?';
    return zones.where((z) => z.id == id).firstOrNull?.name ?? id;
  }

  ShiftDraftSnapshot _snapshotCurrentDraft(List<OperationalZoneView> zones) {
    return ShiftDraftSnapshot(
      originZoneId: _selectedOriginZoneId!,
      destinationZoneId: _selectedDestinationZoneId!,
      originZoneName: _zoneName(_selectedOriginZoneId, zones),
      destinationZoneName: _zoneName(_selectedDestinationZoneId, zones),
      selectedDays: Set.of(_selectedDays),
      arrivalTime: _arrivalTime!,
      departureTime: _departureTime!,
      timezone: _timezone,
      requiredVehicleCategory: _requiredVehicleCategory,
      baseValueCents: parseReaisToCents(_baseValueController.text),
      delayToleranceMinutes: int.tryParse(_delayToleranceController.text) ?? 15,
      earlyArrivalToleranceMinutes:
          int.tryParse(_earlyArrivalToleranceController.text) ?? 5,
      dwellTimeMinutes: int.tryParse(_dwellTimeController.text) ?? 3,
      noShowPenaltyBps: (parseDouble(_noShowMultiplierController.text) * 10000)
          .round(),
      noShowThresholdMinutes:
          int.tryParse(_noShowThresholdController.text) ?? 60,
      delayPenaltyCentsPerMinute: parseReaisToCents(
        _delayMinuteValueController.text,
      ),
      downgradePenaltyCents: parseReaisToCents(_downgradeValueController.text),
      gracePeriodMinutes: int.tryParse(_gracePeriodController.text) ?? 0,
      weekCycle: _weekCycle,
    );
  }

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
      _arrivalTime = null;
      _departureTime = null;
    });
    _baseValueController.text = '';
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

  String? _validateStep0() {
    if (_selectedOriginZoneId == null || _selectedDestinationZoneId == null) {
      return 'Selecione a Zona de Partida e a Zona de Chegada para continuar.';
    }
    if (_selectedOriginZoneId == _selectedDestinationZoneId) {
      return 'A Zona de Partida e Chegada devem ser diferentes.';
    }
    final zones = ref.read(operationalZonesProvider).value ?? [];
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

  String? _validateStep1() {
    if (_selectedDays.isEmpty) {
      return 'Selecione ao menos um dia da semana para o turno.';
    }
    if (_arrivalTime == null || _departureTime == null) {
      return 'Defina os horários de Chegada e Partida do turno.';
    }
    return null;
  }

  String? _validateStep2() {
    final baseVal = parseReaisToCents(_baseValueController.text);
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

  void _onStepTapped(int step) {
    if (step == _currentStep) return;

    if (step < _currentStep) {
      setState(() {
        _errorMessage = null;
        _currentStep = step;
      });
      return;
    }

    if (step > _highestStepReached) {
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
      setState(() {
        _errorMessage = null;
        _currentStep = step;
        if (step > _highestStepReached) _highestStepReached = step;
      });
      return;
    }

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

  void _addReturnShift() {
    if (_currentStep != 2) return;
    final baseVal = parseReaisToCents(_baseValueController.text);
    if (baseVal <= 0) {
      setState(
        () => _errorMessage =
            'O valor base da viagem contratada não pode ser zero antes de adicionar outro turno.',
      );
      return;
    }

    final zones = ref.read(operationalZonesProvider).value ?? [];
    final snapshot = _snapshotCurrentDraft(zones);

    setState(() {
      _confirmedShiftDrafts.add(snapshot);
      _errorMessage = null;
      _currentStep = 1;
    });

    _resetForReturnShift();
  }

  // ── Submit ───────────────────────────────────────────────────

  String _computeHash(List<ShiftPattern> patterns, int baseValueCents) {
    final payload = {
      'contract_id': widget.contractId,
      'base_value_cents': baseValueCents,
      'patterns': patterns
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

  ShiftPattern _draftToPattern(ShiftDraftSnapshot d, int index) {
    final penalties = SLAPenalties.create(
      noShowPenaltyBps: d.noShowPenaltyBps,
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
      arrivalTimeLocal: formatTime(d.arrivalTime),
      departureTimeLocal: formatTime(d.departureTime),
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
    final sessionId = ref.read(currentSessionIdProvider) ?? '';
    if (organizationId == null || operatorId == null) {
      setState(() => _errorMessage = 'Sessão inválida. Faça login novamente.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final zones = ref.read(operationalZonesProvider).value ?? [];
      final finalSnapshot = _snapshotCurrentDraft(zones);
      final allDrafts = [..._confirmedShiftDrafts, finalSnapshot];

      final patterns = <ShiftPattern>[];
      for (var i = 0; i < allDrafts.length; i++) {
        patterns.add(_draftToPattern(allDrafts[i], i));
      }

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

      final notifier = ref.read(
        contractCommandNotifierProvider(widget.contractId).notifier,
      );

      final planId = await notifier.declareContractualPlan(
        contractId: widget.contractId,
        organizationId: organizationId,
        declaredByUserId: operatorId,
        sessionId: sessionId,
        planVersion: nextVersion,
        originalFileHash: _computeHash(patterns, baseValueCents),
        declaredAtUtc: DateTime.now().toUtc(),
        shiftPatterns: patterns,
        contractualValueCents: baseValueCents,
      );

      if (planId != null && mounted) {
        Navigator.of(context).pop(true);
      } else {
        // [Forensic Error Display] Read status from notifier
        final status = ref
            .read(contractCommandNotifierProvider(widget.contractId))
            .status;
        if (status is AsyncError) {
          setState(
            () => _errorMessage = status.error.toString().replaceAll(
              'Exception: ',
              '',
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _errorMessage = 'Erro inesperado: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── UI Builders ──────────────────────────────────────────────

  Widget _buildStep2() {
    return ShiftPatternStep(
      confirmedShiftsCount: _confirmedShiftDrafts.length,
      originName: _selectedOriginZone?.name ?? _selectedOriginZoneId ?? '—',
      destName:
          _selectedDestinationZone?.name ?? _selectedDestinationZoneId ?? '—',
      selectedDays: _selectedDays,
      departureTime: _departureTime,
      arrivalTime: _arrivalTime,
      timezone: _timezone,
      requiredVehicleCategory: _requiredVehicleCategory,
      weekCycle: _weekCycle,
      onDayToggled: (day, selected) => setState(() {
        if (selected) {
          _selectedDays.add(day);
        } else {
          _selectedDays.remove(day);
        }
        _onDataChanged();
      }),
      onDepartureTimeChanged: (time) => setState(() {
        _departureTime = time;
        _onDataChanged();
      }),
      onArrivalTimeChanged: (time) => setState(() {
        _arrivalTime = time;
        _onDataChanged();
      }),
      onTimezoneChanged: (tz) => setState(() {
        _timezone = tz;
        _onDataChanged();
      }),
      onVehicleCategoryChanged: (c) => setState(() {
        _requiredVehicleCategory = c;
        _onDataChanged();
      }),
      onWeekCycleChanged: (c) => setState(() {
        _weekCycle = c;
        _onDataChanged();
      }),
    );
  }

  Widget _buildStep3() {
    return Step3SlaPenalties(
      baseValueController: _baseValueController,
      delayToleranceController: _delayToleranceController,
      earlyArrivalToleranceController: _earlyArrivalToleranceController,
      dwellTimeController: _dwellTimeController,
      gracePeriodController: _gracePeriodController,
      noShowMultiplierController: _noShowMultiplierController,
      noShowThresholdController: _noShowThresholdController,
      delayMinuteValueController: _delayMinuteValueController,
      downgradeValueController: _downgradeValueController,
      baseValueFocus: _baseValueFocus,
      delayToleranceFocus: _delayToleranceFocus,
      noShowMultiplierFocus: _noShowMultiplierFocus,
      delayMinuteValueFocus: _delayMinuteValueFocus,
      downgradeValueFocus: _downgradeValueFocus,
      earlyArrivalFocus: _earlyArrivalFocus,
      dwellTimeFocus: _dwellTimeFocus,
      noShowThresholdFocus: _noShowThresholdFocus,
      gracePeriodFocus: _gracePeriodFocus,
      onContinue: _onStepContinue,
    );
  }

  Widget _buildStep4() {
    final zones = ref.watch(operationalZonesProvider).value ?? [];
    final allTurns = [
      ..._confirmedShiftDrafts,
      if (_selectedOriginZoneId != null &&
          _selectedDestinationZoneId != null &&
          _arrivalTime != null &&
          _departureTime != null)
        _snapshotCurrentDraft(zones),
    ];
    return ReviewStep(allTurns: allTurns, contractId: widget.contractId);
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Watch status for spinner
    final commandStatus = ref.watch(
      contractCommandNotifierProvider(
        widget.contractId,
      ).select((s) => s.status),
    );
    final isLoading = commandStatus is AsyncLoading || _isSubmitting;

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
            DeclarePlanDialogHeader(
              contractName: widget.contractName,
              confirmedShiftsCount: _confirmedShiftDrafts.length,
              onClose: () => Navigator.of(context).pop(false),
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
                          onPressed: isLoading ? null : details.onStepContinue,
                          icon: isLoading
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
                        if (isStep3)
                          OutlinedButton.icon(
                            onPressed: isLoading ? null : _addReturnShift,
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('+ Adicionar Turno de Retorno'),
                          ),
                        TextButton(
                          onPressed: isLoading ? null : details.onStepCancel,
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
                    content: DeclarePlanZonesStep(
                      contractorName: widget.contractorName,
                      selectedOriginZone: _selectedOriginZone,
                      selectedOriginZoneId: _selectedOriginZoneId,
                      selectedDestinationZone: _selectedDestinationZone,
                      selectedDestinationZoneId: _selectedDestinationZoneId,
                      onOriginChanged: (zone) => setState(() {
                        _selectedOriginZone = zone;
                        _selectedOriginZoneId = zone?.id;
                        _onDataChanged();
                      }),
                      onOriginConfigured: (zone) => setState(() {
                        _selectedOriginZone = zone;
                        _onDataChanged();
                      }),
                      onDestinationChanged: (zone) => setState(() {
                        _selectedDestinationZone = zone;
                        _selectedDestinationZoneId = zone?.id;
                        _onDataChanged();
                      }),
                      onDestinationConfigured: (zone) => setState(() {
                        _selectedDestinationZone = zone;
                        _onDataChanged();
                      }),
                      onSwap: () {
                        setState(() {
                          final tmpZone = _selectedOriginZone;
                          _selectedOriginZone = _selectedDestinationZone;
                          _selectedDestinationZone = tmpZone;
                          final tmpId = _selectedOriginZoneId;
                          _selectedOriginZoneId = _selectedDestinationZoneId;
                          _selectedDestinationZoneId = tmpId;
                          _onDataChanged();
                        });
                      },
                    ),
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
