import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/projections/models/audit_log_projection.dart';

/// The pure state representing the active filters applied to the Audit Log View.
class AuditFilterState extends Equatable {
  final DateTime? startDate;
  final DateTime? endDate;
  final String? eventType;
  final String? category;
  final String? entityId; // e.g. Specific vehicle or driver
  final bool
  silentMode; // true = show only exceptions (management by exception)

  const AuditFilterState({
    this.startDate,
    this.endDate,
    this.eventType,
    this.category,
    this.entityId,
    this.silentMode = true,
  });

  AuditFilterState copyWith({
    DateTime? startDate,
    DateTime? endDate,
    String? eventType,
    String? category,
    String? entityId,
    bool? silentMode,
    bool clearDates = false,
    bool clearEventType = false,
    bool clearCategory = false,
    bool clearEntityId = false,
  }) {
    return AuditFilterState(
      startDate: clearDates ? null : (startDate ?? this.startDate),
      endDate: clearDates ? null : (endDate ?? this.endDate),
      eventType: clearEventType ? null : (eventType ?? this.eventType),
      category: clearCategory ? null : (category ?? this.category),
      entityId: clearEntityId ? null : (entityId ?? this.entityId),
      silentMode: silentMode ?? this.silentMode,
    );
  }

  @override
  List<Object?> get props => [
    startDate,
    endDate,
    eventType,
    category,
    entityId,
    silentMode,
  ];
}

/// The Notifier governing the active filters.
class AuditFilterNotifier extends Notifier<AuditFilterState> {
  @override
  AuditFilterState build() {
    return const AuditFilterState();
  }

  void setDateRange(DateTime start, DateTime end) {
    state = state.copyWith(startDate: start, endDate: end);
  }

  void clearDates() {
    state = state.copyWith(clearDates: true);
  }

  void setCategory(String category) {
    state = state.copyWith(category: category);
  }

  void clearCategory() {
    state = state.copyWith(clearCategory: true);
  }

  void setEntity(String entityId) {
    state = state.copyWith(entityId: entityId);
  }

  void toggleSilentMode() {
    state = state.copyWith(silentMode: !state.silentMode);
  }

  void clearAll() {
    state = const AuditFilterState();
  }
}

/// The globally accessible provider for the Audit Filters.
final auditFilterProvider =
    NotifierProvider<AuditFilterNotifier, AuditFilterState>(
      AuditFilterNotifier.new,
    );

/// The globally accessible provider explicitly holding the "Toggled" audit log
/// for the persistent right-side panel without triggering full-width redraws via modais.
class _SelectedAuditLogNotifier extends Notifier<AuditLogEntry?> {
  @override
  AuditLogEntry? build() => null;

  void set(AuditLogEntry? value) => state = value;
}

final selectedAuditLogProvider =
    NotifierProvider<_SelectedAuditLogNotifier, AuditLogEntry?>(
      _SelectedAuditLogNotifier.new,
    );
