import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:busflow/core/theme/app_theme.dart';
import 'package:busflow/domain/enums/event_type.dart';
import 'package:busflow/state/providers/fleet_providers.dart';
import 'package:busflow/state/providers/authority_providers.dart';
import 'package:busflow/application/authority/operational_command_bus.dart';

/// Modal for registering an operational occurrence on a trip.
///
/// Allows the operator to select event type, severity, and add notes.
/// On confirm, creates a TripEvent via OperationalControlFacade.
class OccurrenceModal extends ConsumerStatefulWidget {
  final String tripId;
  final String tripLabel;

  const OccurrenceModal({
    super.key,
    required this.tripId,
    required this.tripLabel,
  });

  /// Show the modal as a dialog
  static Future<bool?> show(
    BuildContext context, {
    required String tripId,
    required String tripLabel,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => OccurrenceModal(tripId: tripId, tripLabel: tripLabel),
    );
  }

  @override
  ConsumerState<OccurrenceModal> createState() => _OccurrenceModalState();
}

class _OccurrenceModalState extends ConsumerState<OccurrenceModal> {
  EventType _selectedType = EventType.manualOverride;
  String _severity = 'medium';
  final _notesController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: BusFlowColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.report_problem_outlined,
                  color: BusFlowColors.delayed,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Registrar Ocorrência',
                    style: BusFlowTypography.sectionTitle,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.pop(context, false),
                  color: BusFlowColors.textSecondary,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(widget.tripLabel, style: BusFlowTypography.caption),
            const Divider(color: BusFlowColors.border, height: 20),

            // Event Type
            Text('Tipo de Evento', style: BusFlowTypography.caption),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: BusFlowColors.border),
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<EventType>(
                  value: _selectedType,
                  isExpanded: true,
                  dropdownColor: BusFlowColors.surface,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  style: BusFlowTypography.bodyMedium,
                  items: EventType.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Row(
                        children: [
                          Icon(
                            type.icon,
                            size: 16,
                            color: _severityColor(type),
                          ),
                          const SizedBox(width: 8),
                          Text(type.label),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _selectedType = value);
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Severity
            Text('Severidade', style: BusFlowTypography.caption),
            const SizedBox(height: 6),
            Row(
              children: [
                _SeverityChip(
                  label: 'Baixa',
                  color: BusFlowColors.onTime,
                  isSelected: _severity == 'low',
                  onTap: () => setState(() => _severity = 'low'),
                ),
                const SizedBox(width: 6),
                _SeverityChip(
                  label: 'Média',
                  color: BusFlowColors.delayed,
                  isSelected: _severity == 'medium',
                  onTap: () => setState(() => _severity = 'medium'),
                ),
                const SizedBox(width: 6),
                _SeverityChip(
                  label: 'Alta',
                  color: BusFlowColors.critical,
                  isSelected: _severity == 'high',
                  onTap: () => setState(() => _severity = 'high'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Notes
            Text('Observação', style: BusFlowTypography.caption),
            const SizedBox(height: 6),
            TextField(
              controller: _notesController,
              maxLines: 3,
              style: BusFlowTypography.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Descreva a ocorrência...',
                hintStyle: BusFlowTypography.caption,
                filled: true,
                fillColor: BusFlowColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: BusFlowColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: BusFlowColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: BusFlowColors.primary),
                ),
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
            const SizedBox(height: 20),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(color: BusFlowColors.textSecondary),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _isSubmitting ? null : _submit,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check, size: 16),
                  label: const Text('Confirmar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: BusFlowColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);

    final facade = ref.read(operationalControlFacadeProvider);

    try {
      await facade.createTripEvent(
        tripId: widget.tripId,
        type: _selectedType,
        metadata: {'severity': _severity},
        notes: _notesController.text.isNotEmpty ? _notesController.text : null,
      );

      triggerUIRefresh(ref);

      if (mounted) {
        Navigator.pop(context, true);
      }
    } on UnauthorizedActionException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Acesso Negado: ${e.reason}'),
            backgroundColor: BusFlowColors.critical,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Color _severityColor(EventType type) {
    switch (type.severity) {
      case EventSeverity.warning:
        return BusFlowColors.delayed;
      case EventSeverity.info:
        return BusFlowColors.onTime;
      case EventSeverity.neutral:
        return BusFlowColors.textSecondary;
    }
  }
}

class _SeverityChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _SeverityChip({
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? color : BusFlowColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? color : BusFlowColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
