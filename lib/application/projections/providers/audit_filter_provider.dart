import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/audit_log_projection.dart';

/// The pure state representing the active filters applied to the Audit Log View.
class AuditFilterState {
  final DateTime? startDate;
  final DateTime? endDate;
  final String? eventType;
  final String? category;
  final String? entityId; // e.g. Specific vehicle or driver

  const AuditFilterState({
    this.startDate,
    this.endDate,
    this.eventType,
    this.category,
    this.entityId,
  });

  AuditFilterState copyWith({
    DateTime? startDate,
    DateTime? endDate,
    String? eventType,
    String? category,
    String? entityId,
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
    );
  }
}

/// The StateNotifier governing the active filters.
class AuditFilterNotifier extends StateNotifier<AuditFilterState> {
  AuditFilterNotifier() : super(const AuditFilterState());

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

  void clearAll() {
    state = const AuditFilterState();
  }
}

/// The globally accessible provider for the Audit Filters.
final auditFilterProvider =
    StateNotifierProvider<AuditFilterNotifier, AuditFilterState>((ref) {
      return AuditFilterNotifier();
    });

/// The globally accessible provider explicitly holding the "Toggled" audit log
/// for the persistent right-side panel without triggering full-width redraws via modais.
final selectedAuditLogProvider = StateProvider<AuditLogEntry?>((ref) => null);
