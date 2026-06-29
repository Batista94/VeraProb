import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/operational_control_service.dart'
    show OperationalTrip, TripStatus;
import 'package:veraprob/application/sla_audit/sla_ledger_mapper.dart'
    show SlaLedgerEntry;
import 'package:veraprob/presentation/shared/trip_status_theme.dart';
import 'package:veraprob/application/intelligence/suggestion_engine.dart'
    show OperationalSuggestion, SuggestionAction, SuggestionEngine;
import 'package:veraprob/application/authority/operational_command_bus.dart'
    show UpdateTripStatusCommand;
import 'package:veraprob/state/providers/fleet_providers.dart';
import 'package:veraprob/presentation/shared/ui/status_badge.dart';
import 'package:latlong2/latlong.dart';
import 'package:veraprob/features/admin/presentation/shared/widgets/geofence_evidence_map.dart';
import 'package:veraprob/features/admin/presentation/shared/widgets/reverse_geocoded_address.dart';
import 'occurrence_modal.dart';
import 'package:veraprob/features/admin/presentation/command_center/utils/ui_command_dispatcher.dart';
import 'event_tile_widget.dart';

const Color _kDestructiveAction = Color(0xFFB71C1C);

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
      width: (MediaQuery.sizeOf(context).width * 0.26).clamp(280.0, 360.0),
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

                  // Evidence Mini-Map (collapsed by default)
                  _EvidenceMiniMapSection(trip: trip),

                  const Divider(height: 1, color: VeraProbColors.border),

                  // Event Timeline
                  switch (eventsAsync) {
                    AsyncData(:final value) => _EventTimeline(entries: value),
                    AsyncLoading() => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    AsyncError() => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Não foi possível carregar o histórico do veículo.',
                      ),
                    ),
                  },
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
            '${(trip.completionBps / 100).toStringAsFixed(0)}%',
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
              const Icon(
                Icons.lightbulb,
                color: VeraProbColors.primary,
                size: 18,
              ),
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
            color: _kDestructiveAction,
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
    showDialog<void>(
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
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: effectiveColor),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: effectiveColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Evidence Mini-Map ─────────────────────────────────

class _EvidenceMiniMapSection extends ConsumerWidget {
  final OperationalTrip trip;

  const _EvidenceMiniMapSection({required this.trip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Resolve vehicle position from normalized state
    final statesAsync = ref.watch(normalizedStateProvider);
    final vehicleState = statesAsync.value
        ?.where((s) => s.tripId == trip.id)
        .firstOrNull;

    if (vehicleState == null) return const SizedBox.shrink();

    final vehiclePos = LatLng(vehicleState.latitude, vehicleState.longitude);

    return _CollapsibleSection(
      title: 'EVIDÊNCIA VISUAL',
      icon: Icons.map_outlined,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GeofenceEvidenceMap(
              infractionPoint: vehiclePos,
              markerColor: trip.status.color,
              height: 140,
            ),
            const SizedBox(height: VeraProbSpacing.sm),
            ReverseGeocodedAddress(
              lat: vehicleState.latitude,
              lng: vehicleState.longitude,
            ),
          ],
        ),
      ),
    );
  }
}

class _CollapsibleSection extends StatefulWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _CollapsibleSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 14,
                  color: VeraProbColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: VeraProbTypography.caption.copyWith(
                      letterSpacing: 1.0,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  _isExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                  color: VeraProbColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (_isExpanded) widget.child,
      ],
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
            ...entries.take(15).map((entry) => EventTileWidget(entry: entry)),
        ],
      ),
    );
  }
}
