import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:busflow/core/theme/app_theme.dart';
import 'package:busflow/domain/entities/operational_trip.dart';
import 'package:busflow/domain/entities/trip_event.dart';
import 'package:busflow/domain/enums/event_type.dart';
import 'package:busflow/domain/enums/trip_status.dart';
import 'package:busflow/domain/entities/operational_suggestion.dart';
import 'package:busflow/application/intelligence/suggestion_engine.dart';
import 'package:busflow/state/providers/fleet_providers.dart';
import 'package:busflow/presentation/shared/widgets/status_badge.dart';
import 'occurrence_modal.dart';

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
    final events = ref.watch(selectedTripEventsProvider);
    final suggestion = SuggestionEngine().generateSuggestion(
      ref: ref,
      context: context,
      trip: trip,
    );

    return Container(
      width: 340,
      decoration: const BoxDecoration(
        color: BusFlowColors.surface,
        border: Border(left: BorderSide(color: BusFlowColors.border)),
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

                  const Divider(height: 1, color: BusFlowColors.border),

                  // Intelligent Suggestion
                  if (suggestion != null) ...[
                    _SuggestionSection(suggestion: suggestion),
                    const Divider(height: 1, color: BusFlowColors.border),
                  ],

                  // Action Buttons
                  _ActionsSection(trip: trip),

                  const Divider(height: 1, color: BusFlowColors.border),

                  // Event Timeline
                  _EventTimeline(events: events),
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
        border: const Border(bottom: BorderSide(color: BusFlowColors.border)),
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
                  style: BusFlowTypography.sectionTitle,
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
                        style: BusFlowTypography.caption.copyWith(
                          color: BusFlowColors.delayed,
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
            color: BusFlowColors.textSecondary,
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
          Icon(icon, size: 14, color: BusFlowColors.textDisabled),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Text(label, style: BusFlowTypography.caption),
          ),
          Expanded(
            child: Text(
              value,
              style: BusFlowTypography.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Suggestion Section ────────────────────────────────

class _SuggestionSection extends StatelessWidget {
  final OperationalSuggestion suggestion;

  const _SuggestionSection({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: BusFlowColors.primary.withValues(alpha: 0.05),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb, color: BusFlowColors.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                'SUGESTÃO DO SISTEMA',
                style: BusFlowTypography.caption.copyWith(
                  color: BusFlowColors.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            suggestion.title,
            style: BusFlowTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(suggestion.description, style: BusFlowTypography.caption),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: suggestion.onExecute,
              icon: Icon(suggestion.actionIcon, size: 16),
              label: Text(suggestion.actionLabel),
              style: FilledButton.styleFrom(
                backgroundColor: BusFlowColors.primary,
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
            style: BusFlowTypography.caption.copyWith(
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
                  color: BusFlowColors.onTime,
                  enabled:
                      trip.status == TripStatus.delayed ||
                      trip.status == TripStatus.interrupted,
                  onTap: () => _updateStatus(
                    ref,
                    context,
                    trip.id,
                    TripStatus.enRoute,
                    reason: 'Regularizado pelo operador',
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _ActionButton(
                  icon: Icons.report_problem_outlined,
                  label: 'Ocorrência',
                  color: BusFlowColors.delayed,
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
                  color: BusFlowColors.scheduled,
                  enabled: trip.status.isActive,
                  onTap: () => _updateStatus(
                    ref,
                    context,
                    trip.id,
                    TripStatus.dispatched,
                    reason: 'Redespachado pelo operador',
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _ActionButton(
                  icon: Icons.pause_circle_outline,
                  label: 'Interromper',
                  color: BusFlowColors.critical,
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
                    onConfirm: () => _updateStatus(
                      ref,
                      context,
                      trip.id,
                      TripStatus.interrupted,
                      reason: 'Interrompido pelo operador',
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
              onConfirm: () => _updateStatus(
                ref,
                context,
                trip.id,
                TripStatus.cancelled,
                reason: 'Cancelado pelo operador',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateStatus(
    WidgetRef ref,
    BuildContext context,
    String tripId,
    TripStatus newStatus, {
    String? reason,
  }) async {
    final control = ref.read(operationalControlProvider);
    await control.updateTripStatus(tripId, newStatus, reason: reason);
    triggerUIRefresh(ref);
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
        backgroundColor: BusFlowColors.surface,
        title: Text(title, style: BusFlowTypography.sectionTitle),
        content: Text(message, style: BusFlowTypography.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Não',
              style: TextStyle(color: BusFlowColors.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            style: FilledButton.styleFrom(
              backgroundColor: destructive
                  ? BusFlowColors.critical
                  : BusFlowColors.primary,
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
    final effectiveColor = enabled ? color : BusFlowColors.textDisabled;

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
  final List<TripEvent> events;

  const _EventTimeline({required this.events});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HISTÓRICO DE EVENTOS',
            style: BusFlowTypography.caption.copyWith(
              letterSpacing: 1.0,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),

          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Nenhum evento registrado',
                style: BusFlowTypography.bodySmall,
              ),
            )
          else
            ...events.take(10).map((event) => _EventTile(event: event)),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final TripEvent event;

  const _EventTile({required this.event});

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
                  color: _eventColor(event),
                  shape: BoxShape.circle,
                  border: Border.all(color: BusFlowColors.surface, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: _eventColor(event).withValues(alpha: 0.5),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
              Container(
                width: 2,
                height: 24, // Fixed height instead of Expanded
                color: BusFlowColors.border,
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
                      event.eventType.icon,
                      size: 12,
                      color: _eventColor(event),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        event.eventType.label,
                        style: BusFlowTypography.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: BusFlowColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      _formatTime(event.createdAt),
                      style: BusFlowTypography.caption.copyWith(fontSize: 10),
                    ),
                  ],
                ),
                Text(event.summary, style: BusFlowTypography.caption),
                if (event.metadata?['notes'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      event.metadata!['notes'],
                      style: BusFlowTypography.caption.copyWith(
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

  Color _eventColor(TripEvent event) {
    switch (event.eventType.severity) {
      case EventSeverity.warning:
        return BusFlowColors.delayed;
      case EventSeverity.info:
        return BusFlowColors.onTime;
      case EventSeverity.neutral:
        return BusFlowColors.textSecondary;
    }
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }
}
