import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/projections/models/audit_log_projection.dart';

/// The pure state representing the active filters applied to the Audit Log View.
class AuditFilterState extends Equatable {
  final String? category;
  final bool
  silentMode; // true = show only exceptions (management by exception)

  const AuditFilterState({this.category, this.silentMode = true});

  AuditFilterState copyWith({
    String? category,
    bool? silentMode,
    bool clearCategory = false,
  }) {
    return AuditFilterState(
      category: clearCategory ? null : (category ?? this.category),
      silentMode: silentMode ?? this.silentMode,
    );
  }

  @override
  List<Object?> get props => [category, silentMode];
}

/// The Notifier governing the active filters.
class AuditFilterNotifier extends Notifier<AuditFilterState> {
  @override
  AuditFilterState build() {
    return const AuditFilterState();
  }

  void setCategory(String category) {
    state = state.copyWith(category: category);
  }

  void clearCategory() {
    state = state.copyWith(clearCategory: true);
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
