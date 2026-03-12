import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:busflow/application/sla_audit/declare_contractual_plan_command.dart';
import 'package:busflow/core/theme/app_theme.dart';
import 'package:busflow/domain/sla_audit/domain_exception.dart';
import 'package:busflow/domain/sla_audit/shift_pattern.dart';
import 'package:busflow/domain/sla_audit/sla_penalties.dart';
import 'package:busflow/domain/shared/money.dart';
import 'package:busflow/state/providers/auth_providers.dart';
import 'package:busflow/state/providers/contract_providers.dart';
import 'package:busflow/state/providers/operational_zone_providers.dart';
import 'package:busflow/state/providers/sla_providers.dart';


/// Dialog form for declaring a new B2B Plan for an existing contract.
///
/// Translated using /B2B-OCC-Translator:
/// - Replaces raw Lat/Lng with "Zonas Operacionais"
/// - Replaces raw UTC timestamps with "Padrões de Turno"
/// - Uses CFO-friendly terminology for SLA Penalties
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

  // -- Step 1: Zonas Operacionais (Origin/Destination)
  String? _selectedOriginZoneId;
  String? _selectedDestinationZoneId;

  // -- Step 2: Padrão de Turno (Schedule)
  final Set<int> _selectedDays = {1, 2, 3, 4, 5}; // Seg-Sex
  TimeOfDay? _arrivalTime;
  TimeOfDay? _departureTime;
  String _timezone = 'America/Sao_Paulo';

  // -- Step 3: SLA & Penalidades (Financials)
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

  // --- Helpers for parsing financial inputs ---
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

  // --- Stepper Navigation ---

  void _onStepContinue() {
    if (_currentStep == 0) {
      if (_selectedOriginZoneId == null || _selectedDestinationZoneId == null) {
        setState(() {
          _errorMessage =
              'Selecione a Zona de Partida e a Zona de Chegada para continuar.';
        });
        return;
      }
      if (_selectedOriginZoneId == _selectedDestinationZoneId) {
        setState(() {
          _errorMessage = 'A Zona de Partida e Chegada devem ser diferentes.';
        });
        return;
      }
    } else if (_currentStep == 1) {
      if (_selectedDays.isEmpty) {
        setState(() {
          _errorMessage = 'Selecione ao menos um dia da semana para o turno.';
        });
        return;
      }
      if (_arrivalTime == null || _departureTime == null) {
        setState(() {
          _errorMessage = 'Defina os horários de Chegada e Partida do turno.';
        });
        return;
      }
    } else if (_currentStep == 2) {
      final baseVal = _parseReaisToCents(_baseValueController.text);
      if (baseVal <= 0) {
        setState(() {
          _errorMessage = 'O valor base da viagem contratada não pode ser zero.';
        });
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

  // --- Submit ---

  String _formatTime(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

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
              })
          .toList(),
    };
    final json = jsonEncode(payload);
    return sha256.convert(utf8.encode(json)).toString();
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
      final baseValueCents = _parseReaisToCents(_baseValueController.text);
      final delayCents = _parseReaisToCents(_delayMinuteValueController.text);
      final downgradeCents = _parseReaisToCents(_downgradeValueController.text);
      final noShowMult = _parseDouble(_noShowMultiplierController.text);
      final tolerance = int.tryParse(_delayToleranceController.text) ?? 15;
      final noShowThreshold = int.tryParse(_noShowThresholdController.text) ?? 60;
      final earlyArrival = int.tryParse(_earlyArrivalToleranceController.text) ?? 5;
      final dwellTime = int.tryParse(_dwellTimeController.text) ?? 3;

      final penalties = SLAPenalties.create(
        noShowPenaltyMultiplier: noShowMult,
        delayToleranceMinutes: tolerance,
        delayPenaltyPerMinute: Money(delayCents),
        downgradePenaltyFlat: Money(downgradeCents),
        noShowThresholdMinutes: noShowThreshold,
        earlyArrivalToleranceMinutes: earlyArrival,
        dwellTimeMinutes: dwellTime,
      );

      final pattern = ShiftPattern.create(
        index: 0,
        daysOfWeek: _selectedDays.map((v) => DayOfWeek.fromValue(v)).toList(),
        arrivalTimeLocal: _formatTime(_arrivalTime!),
        departureTimeLocal: _formatTime(_departureTime!),
        timezone: _timezone,
        originZoneId: _selectedOriginZoneId!,
        destinationZoneId: _selectedDestinationZoneId!,
        penalties: penalties,
      );

      final planRepo = ref.read(planDeclarationRepositoryProvider);
      final existing = await planRepo.findByContract(
        widget.contractId,
        organizationId: organizationId,
      );
      final nextVersion = existing.isEmpty
          ? 1
          : existing.map((p) => p.planVersion).reduce((a, b) => a > b ? a : b) + 1;

      // Create command WITHOUT hash to compute it deterministically
      var cmd = DeclareContractualPlanCommand(
        organizationId: organizationId,
        contractId: widget.contractId,
        declaredByUserId: operatorId,
        planVersion: nextVersion,
        originalFileHash: '', // temp
        declaredAtUtc: DateTime.now().toUtc(),
        shiftPatterns: [pattern],
        contractualValueCents: baseValueCents,
      );

      // Mutate command with final hash
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

  // --- UI Builders ---

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
                  color: hasGeofence
                      ? BusFlowColors.onTime
                      : BusFlowColors.warning,
                ),
                const SizedBox(width: 8),
                Text(zone.name),
              ],
            ),
          );
        }).toList();

        // Geofence warning for selected zones
        final originZone = zones.where((z) => z.id == _selectedOriginZoneId).firstOrNull;
        final destZone = zones.where((z) => z.id == _selectedDestinationZoneId).firstOrNull;
        final missingGeofence = [originZone, destZone]
            .where((z) => z != null && z.geofence == null)
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Selecione as zonas operacionais (geofences) que delineiam esta rota B2B. As coordenadas reais serão blindadas.',
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
                  onChanged: (val) => setState(() => _selectedDestinationZoneId = val),
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
                        '${missingGeofence.map((z) => z!.name).join(', ')} não possui geofence configurado — '
                        'a engine de projeção não conseguirá validar chegada/partida automaticamente.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: BusFlowColors.warning,
                        ),
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
      1: 'Seg',
      2: 'Ter',
      3: 'Qua',
      4: 'Qui',
      5: 'Sex',
      6: 'Sáb',
      7: 'Dom',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Padrão de recorrência. Quando este turno ocorre e quais os horários da operação?',
          style: TextStyle(color: BusFlowColors.textSecondary),
        ),
        const SizedBox(height: 20),
        const Text('Dias da Semana',
            style: TextStyle(fontWeight: FontWeight.w600)),
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
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cláusulas contratuais B2B. Configure os ofensores financeiros e janelas operacionais para descumprimento do Nível de Serviço (SLA).',
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

        // ── Grupo 1: Pontualidade e Janelas Operacionais ──
        _SectionHeader(
          icon: Icons.schedule,
          label: 'Pontualidade e Janelas Operacionais',
        ),
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

        // ── Grupo 2: Falhas Críticas ──
        _SectionHeader(
          icon: Icons.warning_amber_rounded,
          label: 'Falhas Críticas (Cláusulas de Penalidade)',
        ),
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
                    message: 'Alavanca Financeira: penalidade aplicada ao valor base '
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
                    message: 'Atraso (em minutos) a partir do qual o sistema '
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

        // ── Grupo 3: Qualidade da Frota ──
        _SectionHeader(
          icon: Icons.directions_bus,
          label: 'Qualidade da Frota',
        ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Revise o contrato antes de publicar.',
          style: TextStyle(color: BusFlowColors.textSecondary),
        ),
        const SizedBox(height: 20),
        Card(
          color: BusFlowColors.info.withValues(alpha: 0.15),
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Padrão de Fretamento B2B configurado com sucesso.',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: BusFlowColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'A engine de projeção irá automaticamente calcular e imobilizar no banco de dados as viagens ('
                  'Viagens Programadas) para os próximos 30 dias com base nos dias e horários selecionados.\n\n'
                  'Todas as zonas operacionais terão suas coordenadas blindadas no snapshot da projeção para proteção de auditoria retroativa.',
                  style: TextStyle(color: BusFlowColors.textPrimary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          '⚠️ Após publicado, este Padrão de Turno não poderá ser modificado diretamente. Uma nova versão do plano precisará ser declarada.',
          style: TextStyle(color: BusFlowColors.warning, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
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
                          style: TextStyle(
                            fontSize: 12,
                            color: BusFlowColors.textSecondary,
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
                    border: Border.all(color: BusFlowColors.error.withValues(alpha: 0.3)),
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
                  return Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Row(
                      children: [
                        FilledButton.icon(
                          onPressed: _isSubmitting ? null : details.onStepContinue,
                          icon: _isSubmitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : Icon(isLastStep
                                  ? Icons.publish
                                  : Icons.arrow_forward),
                          label: Text(
                              isLastStep ? 'Publicar SLA B2B' : 'Continuar'),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: _isSubmitting ? null : details.onStepCancel,
                          child: Text(_currentStep == 0 ? 'Cancelar' : 'Voltar'),
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

/// Section header widget for Step 3 SLA groups.
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
