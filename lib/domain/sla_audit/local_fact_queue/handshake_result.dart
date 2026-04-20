import 'package:equatable/equatable.dart';

/// Result returned by [SyncHandshakeService.performHandshake].
///
/// Describes the gap between what the OCC last acknowledged and what the
/// Supabase backend currently holds for this organisation.
///
/// **INV-9:** [lastServerFactReceivedAt] is always UTC.
/// **INV-18:** Pure Dart — zero Flutter / Supabase dependencies.
class HandshakeResult extends Equatable {
  /// UTC timestamp of the most recent [canonical_fact] on the server for this
  /// organisation.  Used to advance the client anchor after a successful sync.
  final DateTime lastServerFactReceivedAt;

  /// IDs of [CanonicalFact] records the client missed while offline.
  /// Empty when the client is fully caught up.
  final List<String> missingFactIds;

  const HandshakeResult({
    required this.lastServerFactReceivedAt,
    required this.missingFactIds,
  });

  /// `true` when the client missed at least one fact.
  bool get hasGaps => missingFactIds.isNotEmpty;

  @override
  List<Object?> get props => [lastServerFactReceivedAt, missingFactIds];
}
