import 'package:flutter/material.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';

import 'package:veraprob/features/admin/presentation/screens/widgets/declare_plan/declare_plan_ui_utils.dart';


/// Step 2 of the Declare Contract Plan wizard — Shift Pattern.
///
/// Renders day selection, departure/arrival time pickers, timezone dropdown,
/// vehicle category, and week cycle. All mutations are surfaced via callbacks
/// so the parent [_DeclareContractPlanFormState] owns the mutable state.
class ShiftPatternStep extends StatelessWidget {
  const ShiftPatternStep({
    super.key,
    required this.confirmedShiftsCount,
    required this.originName,
    required this.destName,
    required this.selectedDays,
    required this.departureTime,
    required this.arrivalTime,
    required this.timezone,
    required this.requiredVehicleCategory,
    required this.weekCycle,
    required this.onDayToggled,
    required this.onDepartureTimeChanged,
    required this.onArrivalTimeChanged,
    required this.onTimezoneChanged,
    required this.onVehicleCategoryChanged,
    required this.onWeekCycleChanged,
  });

  final int confirmedShiftsCount;
  final String originName;
  final String destName;
  final Set<int> selectedDays;
  final TimeOfDay? departureTime;
  final TimeOfDay? arrivalTime;
  final String timezone;
  final VehicleCategory requiredVehicleCategory;
  final WeekCycle weekCycle;
  final void Function(int day, bool selected) onDayToggled;
  final ValueChanged<TimeOfDay> onDepartureTimeChanged;
  final ValueChanged<TimeOfDay> onArrivalTimeChanged;
  final ValueChanged<String> onTimezoneChanged;
  final ValueChanged<VehicleCategory> onVehicleCategoryChanged;
  final ValueChanged<WeekCycle> onWeekCycleChanged;

  @override
  Widget build(BuildContext context) {
    const daysMap = {
      1: 'Seg',
      2: 'Ter',
      3: 'Qua',
      4: 'Qui',
      5: 'Sex',
      6: 'Sáb',
      7: 'Dom',
    };

    final isReturnShift = confirmedShiftsCount > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          confirmedShiftsCount == 0
              ? 'Configure o padrão de recorrência: dias, horários, fuso e categoria de veículo exigida.'
              : 'Turno ${confirmedShiftsCount + 1} de ${confirmedShiftsCount + 1} — configure o turno de Retorno.',
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
                  'Turno de Retorno ${confirmedShiftsCount + 1}',
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
            final isSelected = selectedDays.contains(e.key);
            return FilterChip(
              label: Text(e.value),
              selected: isSelected,
              onSelected: (selected) => onDayToggled(e.key, selected),
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
                  departureTime != null
                      ? formatTime(departureTime!)
                      : 'Não definido',
                ),
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: const TimeOfDay(hour: 6, minute: 0),
                  );
                  if (time != null) onDepartureTimeChanged(time);
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
                  arrivalTime != null
                      ? formatTime(arrivalTime!)
                      : 'Não definido',
                ),
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: const TimeOfDay(hour: 7, minute: 0),
                  );
                  if (time != null) onArrivalTimeChanged(time);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // ── Fuso Horário ──────────────────────────────────────
        DropdownButtonFormField<String>(
          initialValue: kBrTimezones.contains(timezone)
              ? timezone
              : kBrTimezones.first,
          decoration: const InputDecoration(
            labelText: 'Fuso Horário *',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.schedule),
            helperText:
                'Os horários de chegada/partida serão interpretados neste fuso.',
          ),
          items: kBrTimezones
              .map((tz) => DropdownMenuItem(value: tz, child: Text(tz)))
              .toList(),
          onChanged: (v) => onTimezoneChanged(v ?? timezone),
        ),
        const SizedBox(height: 16),

        // ── Categoria de Veículo Exigida ──────────────────────
        DropdownButtonFormField<VehicleCategory>(
          initialValue: requiredVehicleCategory,
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
              onVehicleCategoryChanged(v ?? requiredVehicleCategory),
        ),
        const SizedBox(height: 16),

        // ── Ciclo de Recorrência (WeekCycle) ──────────────────
        DropdownButtonFormField<WeekCycle>(
          initialValue: weekCycle,
          decoration: const InputDecoration(
            labelText: 'Ciclo de Recorrência *',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.repeat),
            helperText:
                'Define se o turno roda toda semana ou em semanas específicas do ciclo industrial.',
          ),
          items: const [
            DropdownMenuItem(
              value: WeekCycle.everyWeek,
              child: Text('Toda Semana'),
            ),
            DropdownMenuItem(
              value: WeekCycle.weekA,
              child: Text('Semana A (1/4)'),
            ),
            DropdownMenuItem(
              value: WeekCycle.weekB,
              child: Text('Semana B (2/4)'),
            ),
            DropdownMenuItem(
              value: WeekCycle.weekC,
              child: Text('Semana C (3/4)'),
            ),
            DropdownMenuItem(
              value: WeekCycle.weekD,
              child: Text('Semana D (4/4)'),
            ),
          ],
          onChanged: (v) => onWeekCycleChanged(v ?? weekCycle),
        ),
      ],
    );
  }
}
