/// Domain model for audit log payloads to prevent raw Map leaks in UI (SRP).
class AuditLogPayload {
  final Map<String, Object?> before;
  final Map<String, Object?> after;
  final Map<String, Object?> context;

  const AuditLogPayload({
    this.before = const {},
    this.after = const {},
    this.context = const {},
  });

  factory AuditLogPayload.fromRaw(Map<String, Object?>? raw) {
    if (raw == null) return const AuditLogPayload();

    final beforeRaw = raw['before'];
    final afterRaw = raw['after'];
    final contextRaw = raw['context'];

    return AuditLogPayload(
      before: beforeRaw is Map
          ? Map<String, Object?>.from(beforeRaw)
          : const {},
      after: afterRaw is Map ? Map<String, Object?>.from(afterRaw) : const {},
      context: contextRaw is Map
          ? Map<String, Object?>.from(contextRaw)
          : const {},
    );
  }

  bool get hasDiff => before.isNotEmpty && after.isNotEmpty;
  bool get hasContext => context.isNotEmpty;
  bool get isEmpty => before.isEmpty && after.isEmpty && context.isEmpty;

  /// Returns keys that actually changed between before and after.
  List<String> get changedKeys {
    final allKeys = {...before.keys, ...after.keys};
    return allKeys.where((key) {
      return before[key]?.toString() != after[key]?.toString();
    }).toList();
  }
}
