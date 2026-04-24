import 'package:equatable/equatable.dart';

/// Immutable link between an evidence upload and an execution set (INV-7).
///
/// Maps to `telegram_evidence_links` table.
/// Source indicates how the link was created:
/// - 'telegram': auto-linked by heurística temporal
/// - 'manual': linked by operator via admin UI
/// - 'reconciliation': linked by auditor via reconciliation screen
class TelegramEvidenceLink extends Equatable {
  final String id;
  final String organizationId;
  final String evidenceUploadId;
  final String executionSetId;
  final DateTime linkedAtUtc;
  final String? linkedByUserId;
  final String source;

  const TelegramEvidenceLink({
    required this.id,
    required this.organizationId,
    required this.evidenceUploadId,
    required this.executionSetId,
    required this.linkedAtUtc,
    this.linkedByUserId,
    required this.source,
  });

  @override
  List<Object?> get props => [
    id,
    organizationId,
    evidenceUploadId,
    executionSetId,
    linkedAtUtc,
    linkedByUserId,
    source,
  ];
}
