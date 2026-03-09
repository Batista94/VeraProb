import 'package:flutter/foundation.dart';
import '../domain/entities/operational_trip.dart';
import '../domain/entities/trip_event.dart';
import '../domain/enums/event_type.dart';
import '../domain/enums/trip_status.dart';
import '../data/services/fleet_simulation_service.dart';
import 'audit/audit_service.dart';
import 'operational_control_service.dart';
import 'ports/contractual_event_port.dart';

/// Concrete implementation of [OperationalControlService] backed by
/// the in-memory [FleetSimulationService].
///
/// All actions mutate the simulation state and generate audit events.
/// When migrating to Supabase, replace this with [SupabaseControlService].
class SimulationControlService implements OperationalControlService {
  final FleetSimulationService _simulation;
  final AuditService _auditService;
  final ContractualEventPort _contractualEvents;
  final String Function() _getOperatorId;
  final String Function() _getOrganizationId;

  SimulationControlService(
    this._simulation,
    this._auditService,
    this._contractualEvents, {
    required String Function() getOperatorId,
    required String Function() getOrganizationId,
  }) : _getOperatorId = getOperatorId,
       _getOrganizationId = getOrganizationId;

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
          organizationId: _getOrganizationId(),
          operatorId: _getOperatorId(),
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

    // ── Dispatch forensic evidence to the SLA ledger via the module port ──
    final nowUtc = DateTime.now().toUtc();
    final trip = _simulation.getTripById(tripId);

    if (newStatus == TripStatus.interrupted) {
      await _contractualEvents.dispatchTripInterrupted(
        organizationId: _getOrganizationId(),
        tripId: tripId,
        vehicleId: trip?.vehicleId,
        operatorId: _getOperatorId(),
        reason: reason,
        occurredAtUtc: nowUtc,
      );
    } else if (newStatus == TripStatus.cancelled) {
      await _contractualEvents.dispatchTripCancelled(
        organizationId: _getOrganizationId(),
        tripId: tripId,
        vehicleId: trip?.vehicleId,
        operatorId: _getOperatorId(),
        reason: reason,
        occurredAtUtc: nowUtc,
      );
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
          organizationId: _getOrganizationId(),
          operatorId: _getOperatorId(),
          actionType: 'CREATE_INCIDENT_${eventType.name.toUpperCase()}',
          entityId: tripId,
          oldValue: trip?.status.name,
          newValue: trip?.status.name,
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

    // ── Dispatch forensic evidence to the SLA ledger via the module port ──
    await _contractualEvents.dispatchOccurrenceRegistered(
      organizationId: _getOrganizationId(),
      tripId: tripId,
      vehicleId: trip?.vehicleId,
      operatorId: _getOperatorId(),
      occurrenceType: eventType.name,
      notes: notes,
      metadata: metadata ?? const {},
      occurredAtUtc: DateTime.now().toUtc(),
    );

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
