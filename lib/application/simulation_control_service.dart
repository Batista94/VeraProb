import 'package:flutter/foundation.dart';
import '../domain/entities/operational_trip.dart';
import '../domain/entities/trip_event.dart';
import '../domain/enums/event_type.dart';
import '../domain/enums/trip_status.dart';
import '../data/services/fleet_simulation_service.dart';
import 'audit/audit_service.dart';
import 'operational_control_service.dart';
import '../../domain/sla_audit/execution_events.dart';
import '../../domain/sla_audit/sla_audit_ledger_repository.dart';
import 'sla_audit/sla_ledger_mapper.dart';

/// Concrete implementation of [OperationalControlService] backed by
/// the in-memory [FleetSimulationService].
///
/// All actions mutate the simulation state and generate audit events.
/// When migrating to Supabase, replace this with [SupabaseControlService].
class SimulationControlService implements OperationalControlService {
  final FleetSimulationService _simulation;
  final AuditService _auditService;
  final SlaAuditLedgerRepository _ledgerRepo;
  final String Function() _getOperatorId;

  SimulationControlService(
    this._simulation,
    this._auditService,
    this._ledgerRepo, {
    required String Function() getOperatorId,
  }) : _getOperatorId = getOperatorId;

  @override
  Future<TripEvent> updateTripStatus(
    String tripId,
    TripStatus newStatus, {
    String? reason,
  }) async {
    final oldStatus = _simulation.updateTripStatus(tripId, newStatus);

    // Fire-and-forget: Audit logging never blocks operational flow
    _auditService
        .logAction(
          organizationId: 'mock-org-id', // TODO: Inject from Auth Provider
          operatorId: _getOperatorId(), // Use injected operator ID
          actionType: 'TRIP_STATUS_CHANGE',
          entityId: tripId,
          oldValue: oldStatus?.name,
          newValue: newStatus.name,
          reason: reason ?? 'Mudança de status via painel',
        )
        .catchError((e) {
          // In production, log to crashlytics/sentry
          debugPrint('Failed to log audit action: $e');
        });

    final event = _simulation.addEvent(
      tripId: tripId,
      eventType: EventType.statusChange,
      fromStatus: oldStatus,
      toStatus: newStatus,
      metadata: {
        // ignore: use_null_aware_elements
        if (reason != null) 'reason': reason,
        'source': 'operator_manual',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    // ── Dispatch forensic evidence to the SlaAuditLedger ──
    final nowUtc = DateTime.now().toUtc();
    final trip = _simulation.getTripById(tripId);

    if (newStatus == TripStatus.interrupted) {
      final evidence = TripInterruptedEvidence(
        organizationId: 'mock-org-id', // TODO: Inject from Auth Provider
        occurredAtUtc: nowUtc,
        tripId: tripId,
        vehicleId: trip?.vehicleId,
        operatorId: _getOperatorId(), // Use injected operator ID
        reason: reason,
      );
      await _ledgerRepo.append(SlaLedgerMapper.mapToEntry(evidence));
    } else if (newStatus == TripStatus.cancelled) {
      final evidence = TripCancelledEvidence(
        organizationId: 'mock-org-id',
        occurredAtUtc: nowUtc,
        tripId: tripId,
        vehicleId: trip?.vehicleId,
        operatorId: _getOperatorId(),
        reason: reason,
      );
      await _ledgerRepo.append(SlaLedgerMapper.mapToEntry(evidence));
    }

    return event;
  }

  @override
  Future<TripEvent> createTripEvent(
    String tripId,
    EventType eventType, {
    Map<String, dynamic>? metadata,
    String? notes,
  }) async {
    final trip = _simulation.getTripById(tripId);

    // Fire-and-forget: Audit logging never blocks operational flow
    _auditService
        .logAction(
          organizationId: 'mock-org-id', // TODO: Inject from Auth Provider
          operatorId: _getOperatorId(), // Use injected operator ID
          actionType: 'CREATE_INCIDENT_${eventType.name.toUpperCase()}',
          entityId: tripId,
          oldValue: trip?.status.name,
          newValue: trip?.status.name, // Status might not change directly here
          reason: notes ?? 'Incidente reportado manualmente',
        )
        .catchError((e) {
          // In production, log to crashlytics/sentry
          debugPrint('Failed to log audit action: $e');
        });

    final event = _simulation.addEvent(
      tripId: tripId,
      eventType: eventType,
      fromStatus: trip?.status,
      toStatus: trip?.status,
      metadata: {
        ...?metadata,
        // ignore: use_null_aware_elements
        if (notes != null) 'notes': notes,
        'source': 'operator_manual',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    // ── Dispatch forensic evidence to the SlaAuditLedger ──
    final evidence = OccurrenceRegisteredEvidence(
      organizationId: 'mock-org-id', // TODO: Inject from Auth Provider
      occurredAtUtc: DateTime.now().toUtc(),
      tripId: tripId,
      vehicleId: trip?.vehicleId,
      operatorId: _getOperatorId(), // Use injected operator ID
      occurrenceType: eventType.name,
      notes: notes,
      metadata: metadata ?? const {},
    );
    await _ledgerRepo.append(SlaLedgerMapper.mapToEntry(evidence));

    return event;
  }

  @override
  Future<TripEvent> resolveAlert(String tripId) async {
    return updateTripStatus(
      tripId,
      TripStatus.enRoute,
      reason: 'Alerta resolvido pelo operador',
    );
  }

  @override
  List<TripEvent> getEventsForTrip(String tripId) {
    return _simulation.getEventsForTrip(tripId);
  }

  @override
  OperationalTrip? getTripById(String tripId) {
    return _simulation.getTripById(tripId);
  }
}
