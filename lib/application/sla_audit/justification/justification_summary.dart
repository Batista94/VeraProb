import 'package:equatable/equatable.dart';

import 'package:veraprob/domain/sla_audit/justification/justification_status.dart';

/// Read-model projection of a `contractor_justifications` row for the Defense
/// Portal. The raw Supabase Realtime payload is parsed exactly once, at the
/// provider boundary, so presentation never handles `dynamic` (INV-7) and never
/// imports infrastructure (INV-13).
class JustificationSummary extends Equatable {
  const JustificationSummary({
    required this.id,
    required this.status,
    required this.contractId,
    required this.setId,
    required this.category,
    required this.description,
    required this.createdAtUtc,
    required this.reviewedByUserId,
    required this.reviewedAtUtc,
  });

  /// Builds a summary from a raw Supabase Realtime row. Propagates
  /// [ArgumentError] from [JustificationStatus.fromDb] on an unknown status —
  /// zero-trust telemetry must fail loudly, never silently mis-bucket (INV-18).
  factory JustificationSummary.fromRealtimeRow(Map<String, dynamic> row) {
    return JustificationSummary(
      id: row['id'] as String,
      status: JustificationStatus.fromDb(row['status'] as String),
      contractId: row['contract_id'] as String?,
      setId: row['set_id'] as String?,
      category: row['category'] as String?,
      description: row['description'] as String?,
      createdAtUtc: _parseUtc(row['created_at_utc'] as String?),
      reviewedByUserId: row['reviewed_by_user_id'] as String?,
      reviewedAtUtc: _parseUtc(row['reviewed_at_utc'] as String?),
    );
  }

  final String id;
  final JustificationStatus status;
  final String? contractId;
  final String? setId;
  final String? category;
  final String? description;
  final DateTime? createdAtUtc;
  final String? reviewedByUserId;
  final DateTime? reviewedAtUtc;

  bool get isPending => status == JustificationStatus.pending;

  /// Portuguese label for the contestation category (presentation-agnostic).
  String get categoryLabel => switch ((category ?? '').toLowerCase()) {
    'mechanical' => 'Mecânico',
    'force_majeure' => 'Força Maior',
    'traffic' => 'Trânsito',
    'route_deviation' => 'Desvio de Rota',
    'communication' => 'Comunicação',
    _ => 'Outro',
  };

  static DateTime? _parseUtc(String? raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  @override
  List<Object?> get props => [
    id,
    status,
    contractId,
    setId,
    category,
    description,
    createdAtUtc,
    reviewedByUserId,
    reviewedAtUtc,
  ];
}
