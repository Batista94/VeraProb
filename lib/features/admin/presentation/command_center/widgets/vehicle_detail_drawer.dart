import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/domain/entities/operational_trip.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';
import 'package:veraprob/presentation/shared/trip_status_theme.dart';
import 'package:veraprob/domain/enums/trip_status.dart';
import 'package:veraprob/domain/entities/operational_suggestion.dart';
import 'package:veraprob/application/intelligence/suggestion_engine.dart';
import 'package:veraprob/state/providers/fleet_providers.dart';
import 'package:veraprob/presentation/shared/widgets/status_badge.dart';
import 'occurrence_modal.dart';
import 'package:veraprob/domain/authority/commands/trips/update_trip_status_command.dart';
import '../utils/ui_command_dispatcher.dart';

/// Detailed vehicle/trip drawer shown when an operator selects a trip.
///
/// Contains:
/// - Trip info (route, vehicle, driver, status, speed, delay, GPS)
/// - Operational action buttons (regularize, occurrence, redispatch, interrupt, cancel)
/// - Event timeline showing recent TripEvents
class VehicleDetailDrawer extends ConsumerWidget {
  final OperationalTrip trip;
  final VoidCallback onClose;

  const VehicleDetailDrawer({
    super.key,
    required this.trip,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(forensicLedgerProjectionProvider);
    final suggestion = SuggestionEngine().generateSuggestion(trip: trip);

    return Container(
      width: 340,
      decoration: const BoxDecoration(
        color: VeraProbColors.surface,
        border: Border(left: BorderSide(color: VeraProbColors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(-2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Header ───────────────────────────────────
          _DrawerHeader(trip: trip, onClose: onClose),

          // ── Scrollable Body ──────────────────────────
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info Section
                  _InfoSection(trip: trip),

                  const Divider(height: 1, color: VeraProbColors.border),

                  // Intelligent Suggestion
                  if (suggestion != null) ...[
                    _SuggestionSection(suggestion: suggestion, tripId: trip.id),
                    const Divider(height: 1, color: VeraProbColors.border),
                  ],

                  // Action Buttons
                  _ActionsSection(trip: trip),

                  const Divider(height: 1, color: VeraProbColors.border),

                  // Event Timeline
                  eventsAsync.when(
                    data: (entries) => _EventTimeline(entries: entries),
                    loading: () => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, st) => Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Erro ao carregar histórico: $e'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Header ─────────────────────────────────────────────

class _DrawerHeader extends StatelessWidget {
  final OperationalTrip trip;
  final VoidCallback onClose;

  const _DrawerHeader({required this.trip, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: trip.status.color.withValues(alpha: 0.08),
        border: const Border(bottom: BorderSide(color: VeraProbColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 32,
            decoration: BoxDecoration(
              color: trip.status.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trip.routeDisplay,
                  style: VeraProbTypography.sectionTitle,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    StatusBadge(status: trip.status, compact: true),
                    if (trip.delaySeconds > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        trip.delayDisplay,
                        style: VeraProbTypography.caption.copyWith(
                          color: VeraProbColors.delayed,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onClose,
            color: VeraProbColors.textSecondary,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ── Info Section ───────────────────────────────────────

class _InfoSection extends StatelessWidget {
  final OperationalTrip trip;

  const _InfoSection({required this.trip});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _InfoRow(
            Icons.person_outline,
            'Motorista',
            trip.driverName ?? 'Não alocado',
          ),
          _InfoRow(
            Icons.directions_bus_outlined,
            'Veículo',
            trip.vehiclePlate ?? 'Não alocado',
          ),
          _InfoRow(
            Icons.trending_up,
            'Progresso',
            '${trip.completionPct.toStringAsFixed(0)}%',
          ),
          _InfoRow(
            Icons.schedule,
            'Início Programado',
            _formatTime(trip.scheduledStart),
          ),
          if (trip.actualStart != null)
            _InfoRow(
              Icons.play_arrow,
              'Início Real',
              _formatTime(trip.actualStart!),
            ),
          _InfoRow(Icons.source_outlined, 'Fonte', trip.sourceType),
          _InfoRow(Icons.tag, 'ID', trip.id),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: VeraProbColors.textDisabled),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Text(label, style: VeraProbTypography.caption),
          ),
          Expanded(
            child: Text(
              value,
              style: VeraProbTypography.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Suggestion Section ────────────────────────────────

class _SuggestionSection extends ConsumerWidget {
  final OperationalSuggestion suggestion;
  final String tripId;

  const _SuggestionSection({required this.suggestion, required this.tripId});

  VoidCallback _buildCallback(WidgetRef ref) {
    final control = ref.read(operationalControlProvider);
    switch (suggestion.action) {
      case SuggestionAction.cancelTrip:
        return () {
          control.updateTripStatus(
            tripId,
            TripStatus.cancelled,
            reason: 'Cancelado via auto-sugestão (Veículo parado)',
          );
          triggerUIRefresh(ref);
        };
      case SuggestionAction.interruptTrip:
        return () {
          control.updateTripStatus(
            tripId,
            TripStatus.interrupted,
            reason: 'Interrompido via auto-sugestão (Atraso crítico)',
          );
          triggerUIRefresh(ref);
        };
      case SuggestionAction.regularizeTrip:
        return () {
          control.updateTripStatus(
            tripId,
            TripStatus.enRoute,
            reason: 'Regularizado via auto-sugestão (Acompanhado)',
          );
          triggerUIRefresh(ref);
        };
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: VeraProbColors.primary.withValues(alpha: 0.05),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb, color: VeraProbColors.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                'SUGESTÃO DO SISTEMA',
                style: VeraProbTypography.caption.copyWith(
                  color: VeraProbColors.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            suggestion.title,
            style: VeraProbTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(suggestion.description, style: VeraProbTypography.caption),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _buildCallback(ref),
              icon: Icon(suggestion.action.icon, size: 16),
              label: Text(suggestion.actionLabel),
              style: FilledButton.styleFrom(
                backgroundColor: VeraProbColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Actions Section ───────────────────────────────────

class _ActionsSection extends ConsumerWidget {
  final OperationalTrip trip;

  const _ActionsSection({required this.trip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AÇÕES OPERACIONAIS',
            style: VeraProbTypography.caption.copyWith(
              letterSpacing: 1.0,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),

          // Row 1: Regularize + Occurrence
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.check_circle_outline,
                  label: 'Regularizar',
                  color: VeraProbColors.onTime,
                  enabled:
                      trip.status == TripStatus.delayed ||
                      trip.status == TripStatus.interrupted,
                  onTap: () =>
                      _dispatchStatusUpdate(context, ref, TripStatus.enRoute),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _ActionButton(
                  icon: Icons.report_problem_outlined,
                  label: 'Ocorrência',
                  color: VeraProbColors.delayed,
                  enabled: true,
                  onTap: () => _showOccurrenceModal(context, ref),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Row 2: Redispatch + Interrupt
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.refresh,
                  label: 'Redespachar',
                  color: VeraProbColors.scheduled,
                  enabled: trip.status.isActive,
                  onTap: () => _dispatchStatusUpdate(
                    context,
                    ref,
                    TripStatus.dispatched,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _ActionButton(
                  icon: Icons.pause_circle_outline,
                  label: 'Interromper',
                  color: VeraProbColors.critical,
                  enabled:
                      trip.status == TripStatus.enRoute ||
                      trip.status == TripStatus.atStop ||
                      trip.status == TripStatus.delayed,
                  onTap: () => _confirmAction(
                    context,
                    ref,
                    title: 'Interromper Viagem',
                    message:
                        'Confirma a interrupção da viagem ${trip.routeShortName ?? trip.routeId}?',
                    onConfirm: () => _dispatchStatusUpdate(
                      context,
                      ref,
                      TripStatus.interrupted,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Row 3: Cancel (full width, destructive)
          _ActionButton(
            icon: Icons.cancel_outlined,
            label: 'Cancelar Viagem',
            color: const Color(0xFFB71C1C),
            enabled: !trip.status.isTerminal,
            onTap: () => _confirmAction(
              context,
              ref,
              title: 'Cancelar Viagem',
              message:
                  'ATENÇÃO: Esta ação é irreversível.\nConfirma o cancelamento da viagem ${trip.routeShortName ?? trip.routeId}?',
              destructive: true,
              onConfirm: () =>
                  _dispatchStatusUpdate(context, ref, TripStatus.cancelled),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _dispatchStatusUpdate(
    BuildContext context,
    WidgetRef ref,
    TripStatus newStatus,
  ) async {
    final command = UpdateTripStatusCommand(
      tripId: trip.id,
      newStatus: newStatus,
    );

    final success = await UiCommandDispatcher.dispatch(context, ref, command);
    if (success) {
      triggerUIRefresh(ref);
    }
  }

  Future<void> _showOccurrenceModal(BuildContext context, WidgetRef ref) async {
    final result = await OccurrenceModal.show(
      context,
      tripId: trip.id,
      tripLabel: trip.routeDisplay,
    );
    if (result == true) {
      triggerUIRefresh(ref);
    }
  }

  void _confirmAction(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String message,
    bool destructive = false,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VeraProbColors.surface,
        title: Text(title, style: VeraProbTypography.sectionTitle),
        content: Text(message, style: VeraProbTypography.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Não',
              style: TextStyle(color: VeraProbColors.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            style: FilledButton.styleFrom(
              backgroundColor: destructive
                  ? VeraProbColors.critical
                  : VeraProbColors.primary,
            ),
            child: Text(destructive ? 'Sim, Cancelar' : 'Confirmar'),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = enabled ? color : VeraProbColors.textDisabled;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: effectiveColor.withValues(alpha: enabled ? 0.4 : 0.2),
            ),
            color: enabled
                ? effectiveColor.withValues(alpha: 0.06)
                : Colors.transparent,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: effectiveColor),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: effectiveColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Event Timeline ────────────────────────────────────

class _EventTimeline extends StatelessWidget {
  final List<SlaLedgerEntry> entries;

  const _EventTimeline({required this.entries});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HISTÓRICO DE EVIDÊNCIAS FORENSES',
            style: VeraProbTypography.caption.copyWith(
              letterSpacing: 1.0,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),

          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Nenhum evento registrado no Ledger',
                style: VeraProbTypography.bodySmall,
              ),
            )
          else
            ...entries.take(15).map((entry) => _EventTile(entry: entry)),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final SlaLedgerEntry entry;

  const _EventTile({required this.entry});

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
                height: 24, // Fixed height instead of Expanded
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

  IconData _eventIcon(SlaLedgerEntry entry) {
    switch (entry.type) {
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

  String _eventLabel(SlaLedgerEntry entry) {
    switch (entry.type) {
      case 'OCCURRENCE_REGISTERED':
        final type =
            entry.payload['occurrence_type'] as String? ?? 'Desconhecido';
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
        return 'Fato: ${entry.type}';
    }
  }

  String _eventSummary(SlaLedgerEntry entry) {
    switch (entry.type) {
      case 'OCCURRENCE_REGISTERED':
        return 'Registrado pelo CCO';
      case 'TRIP_INTERRUPTED':
      case 'TRIP_CANCELLED':
        return entry.payload['reason'] as String? ?? 'Ação manual';
      case 'EXECUTION_BOUND':
        final vehicle = entry.payload['vehicle_id'] as String? ?? '?';
        return 'Veículo $vehicle atribuído';
      default:
        return 'Audit Entry #${entry.id ?? '-'}';
    }
  }

  Color _eventColor(SlaLedgerEntry entry) {
    switch (entry.type) {
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
