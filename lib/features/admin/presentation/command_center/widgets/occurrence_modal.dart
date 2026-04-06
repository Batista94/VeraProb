import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/operational_control/operational_control_facade.dart'
    show EventType, EventSeverity;
import 'package:veraprob/state/providers/fleet_providers.dart';
import 'package:veraprob/presentation/shared/trip_status_theme.dart';
import 'package:veraprob/state/providers/authority_providers.dart';
import 'package:veraprob/application/authority/operational_command_bus.dart';

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
      backgroundColor: VeraProbColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 400,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Icon(
                    Icons.report_problem_outlined,
                    color: VeraProbColors.delayed,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Registrar Ocorrência',
                      style: VeraProbTypography.sectionTitle,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context, false),
                    color: VeraProbColors.textSecondary,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(widget.tripLabel, style: VeraProbTypography.caption),
              const Divider(color: VeraProbColors.border, height: 20),

              // Event Type
              Text('Tipo de Evento', style: VeraProbTypography.caption),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: VeraProbColors.border),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<EventType>(
                    value: _selectedType,
                    isExpanded: true,
                    dropdownColor: VeraProbColors.surface,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    style: VeraProbTypography.bodyMedium,
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
              Text('Severidade', style: VeraProbTypography.caption),
              const SizedBox(height: 6),
              Row(
                children: [
                  _SeverityChip(
                    label: 'Baixa',
                    color: VeraProbColors.onTime,
                    isSelected: _severity == 'low',
                    onTap: () => setState(() => _severity = 'low'),
                  ),
                  const SizedBox(width: 6),
                  _SeverityChip(
                    label: 'Média',
                    color: VeraProbColors.delayed,
                    isSelected: _severity == 'medium',
                    onTap: () => setState(() => _severity = 'medium'),
                  ),
                  const SizedBox(width: 6),
                  _SeverityChip(
                    label: 'Alta',
                    color: VeraProbColors.critical,
                    isSelected: _severity == 'high',
                    onTap: () => setState(() => _severity = 'high'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Notes
              Text('Observação', style: VeraProbTypography.caption),
              const SizedBox(height: 6),
              TextField(
                controller: _notesController,
                maxLines: 3,
                style: VeraProbTypography.bodyMedium,
                decoration: InputDecoration(
                  hintText: 'Descreva a ocorrência...',
                  hintStyle: VeraProbTypography.caption,
                  filled: true,
                  fillColor: VeraProbColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: VeraProbColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: VeraProbColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: const BorderSide(color: VeraProbColors.primary),
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
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(color: VeraProbColors.textSecondary),
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
                      backgroundColor: VeraProbColors.primary,
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
            backgroundColor: VeraProbColors.critical,
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
        return VeraProbColors.delayed;
      case EventSeverity.info:
        return VeraProbColors.onTime;
      case EventSeverity.neutral:
        return VeraProbColors.textSecondary;
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
            color: isSelected ? color : VeraProbColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? color : VeraProbColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
