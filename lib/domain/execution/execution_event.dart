import 'package:equatable/equatable.dart';
import 'package:veraprob/domain/execution/execution_domain_exception.dart';

enum ExecutionOutcome { success, failed, partial }

/// The immutable forensic record proving an action was executed after authorization.
///
/// Closes the golden thread: requestId → decisionId → idempotencyKey → executionEvent.
class ExecutionEvent extends Equatable {
  final String requestId;
  final String decisionId;
  final String idempotencyKey;
  final String executorId;
  final DateTime startedAt;
  final DateTime completedAt;
  final ExecutionOutcome status;
  final String? errorMessage;
  final Map<String, dynamic> outputSnapshot;
  final int schemaVersion;
  final Map<String, dynamic> metadata;

  const ExecutionEvent.raw({
    required this.requestId,
    required this.decisionId,
    required this.idempotencyKey,
    required this.executorId,
    required this.startedAt,
    required this.completedAt,
    required this.status,
    this.errorMessage,
    required this.outputSnapshot,
    required this.schemaVersion,
    required this.metadata,
  });

  factory ExecutionEvent({
    required String requestId,
    required String decisionId,
    required String idempotencyKey,
    required String executorId,
    required DateTime startedAt,
    required DateTime completedAt,
    required ExecutionOutcome status,
    String? errorMessage,
    required Map<String, dynamic> outputSnapshot,
    int schemaVersion = 1,
    Map<String, dynamic> metadata = const {},
  }) {
    if (completedAt.isBefore(startedAt)) {
      throw const ExecutionDomainException(
        'INV-25: completedAt must be >= startedAt (temporal integrity violation)',
      );
    }

    if (status == ExecutionOutcome.failed &&
        (errorMessage == null || errorMessage.isEmpty)) {
      throw const ExecutionDomainException(
        'INV-25: status=failed requires non-empty errorMessage',
      );
    }

    return ExecutionEvent.raw(
      requestId: requestId,
      decisionId: decisionId,
      idempotencyKey: idempotencyKey,
      executorId: executorId,
      startedAt: startedAt,
      completedAt: completedAt,
      status: status,
      errorMessage: errorMessage,
      outputSnapshot: _deepCopyMap(outputSnapshot),
      schemaVersion: schemaVersion,
      metadata: _deepCopyMap(metadata),
    );
  }

  Duration get duration => completedAt.difference(startedAt);

  Map<String, dynamic> toJson() {
    return {
      'request_id': requestId,
      'decision_id': decisionId,
      'idempotency_key': idempotencyKey,
      'executor_id': executorId,
      'started_at': startedAt.toIso8601String(),
      'completed_at': completedAt.toIso8601String(),
      'duration_ms': duration.inMilliseconds,
      'status': status.name,
      'error_message': errorMessage,
      'output_snapshot': _deepCopyMap(outputSnapshot),
      'schema_version': schemaVersion,
      'metadata': _deepCopyMap(metadata),
    };
  }

  static Map<String, dynamic> _deepCopyMap(Map<String, dynamic> map) {
    final result = <String, dynamic>{};
    for (final entry in map.entries) {
      if (entry.value is Map<String, dynamic>) {
        result[entry.key] = _deepCopyMap(entry.value);
      } else if (entry.value is List) {
        result[entry.key] = List.from(entry.value);
      } else {
        result[entry.key] = entry.value;
      }
    }
    return result;
  }

  @override
  List<Object?> get props => [
    requestId,
    decisionId,
    idempotencyKey,
    executorId,
    startedAt,
    completedAt,
    status,
    errorMessage,
    outputSnapshot,
    schemaVersion,
    metadata,
  ];
}
