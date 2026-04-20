import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/sla_audit/sla_ledger_mapper.dart'
    show SlaLedgerEntry;

class EventTileWidget extends StatelessWidget {
  final SlaLedgerEntry entry;

  const EventTileWidget({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline dot + line
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: _eventColor(entry),
                  shape: BoxShape.circle,
                  border: Border.all(color: VeraProbColors.surface, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: _eventColor(entry).withValues(alpha: 0.5),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              Container(
                width: 2,
                height: 24,
                color: VeraProbColors.border,
                margin: const EdgeInsets.symmetric(vertical: 4),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _eventIcon(entry),
                      size: 12,
                      color: _eventColor(entry),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _eventLabel(entry),
                        style: VeraProbTypography.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: VeraProbColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      _formatTime(entry.occurredAtUtc.toLocal()),
                      style: VeraProbTypography.caption.copyWith(fontSize: 10),
                    ),
                  ],
                ),
                Text(_eventSummary(entry), style: VeraProbTypography.caption),
                if (entry.payload['notes'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      entry.payload['notes'] as String,
                      style: VeraProbTypography.caption.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _eventIcon(SlaLedgerEntry e) {
    switch (e.type) {
      case 'OCCURRENCE_REGISTERED':
        return Icons.report_problem;
      case 'TRIP_INTERRUPTED':
        return Icons.pause_circle;
      case 'TRIP_CANCELLED':
        return Icons.cancel;
      case 'NO_SHOW_DECLARED':
        return Icons.money_off;
      case 'EVIDENCE_GAP_DECLARED':
        return Icons.satellite_alt;
      case 'EXECUTION_BOUND':
        return Icons.link;
      default:
        return Icons.adjust;
    }
  }

  String _eventLabel(SlaLedgerEntry e) {
    switch (e.type) {
      case 'OCCURRENCE_REGISTERED':
        final type = e.payload['occurrence_type'] as String? ?? 'Desconhecido';
        return 'Ocorrência: $type';
      case 'TRIP_INTERRUPTED':
        return 'Viagem Interrompida';
      case 'TRIP_CANCELLED':
        return 'Viagem Cancelada';
      case 'NO_SHOW_DECLARED':
        return 'Veredito: No-Show';
      case 'EVIDENCE_GAP_DECLARED':
        return 'Veredito: Falta Evidência';
      case 'EXECUTION_BOUND':
        return 'Execução Associada';
      default:
        return 'Fato: ${e.type}';
    }
  }

  String _eventSummary(SlaLedgerEntry e) {
    switch (e.type) {
      case 'OCCURRENCE_REGISTERED':
        return 'Registrado pelo CCO';
      case 'TRIP_INTERRUPTED':
      case 'TRIP_CANCELLED':
        return e.payload['reason'] as String? ?? 'Ação manual';
      case 'EXECUTION_BOUND':
        final vehicle = e.payload['vehicle_id'] as String? ?? '?';
        return 'Veículo $vehicle atribuído';
      default:
        return 'Audit Entry #${e.id ?? '-'}';
    }
  }

  Color _eventColor(SlaLedgerEntry e) {
    switch (e.type) {
      case 'TRIP_INTERRUPTED':
      case 'TRIP_CANCELLED':
      case 'NO_SHOW_DECLARED':
        return VeraProbColors.critical;
      case 'OCCURRENCE_REGISTERED':
      case 'EVIDENCE_GAP_DECLARED':
        return VeraProbColors.delayed;
      case 'EXECUTION_BOUND':
        return VeraProbColors.onTime;
      default:
        return VeraProbColors.textSecondary;
    }
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }
}
