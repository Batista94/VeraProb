import 'package:equatable/equatable.dart';

import 'package:veraprob/domain/sla_audit/canonical_fact.dart';

/// A single telemetry packet dropped during normalization, with provenance.
///
/// [batchIndex] is the position within the original
/// `RawTelemetryBatch.coordinates` list, so a rejected packet stays traceable
/// back to the raw payload for forensic chain of custody.
class RejectedPacket extends Equatable {
  final int batchIndex;
  final String reason;

  const RejectedPacket({required this.batchIndex, required this.reason});

  @override
  List<Object?> get props => [batchIndex, reason];
}

/// Outcome of a [TelemetryNormalizationHandler.normalize] run.
///
/// Carries the full accepted-vs-rejected breakdown so callers (and forensic
/// ledger writers) can audit exactly which packets reached the Engine and
/// which were quarantined, and why.
class NormalizationOutcome extends Equatable {
  final List<CanonicalFact> acceptedFacts;
  final List<RejectedPacket> rejectedPackets;

  const NormalizationOutcome({
    required this.acceptedFacts,
    required this.rejectedPackets,
  });

  int get acceptedCount => acceptedFacts.length;
  int get rejectedCount => rejectedPackets.length;

  @override
  List<Object?> get props => [acceptedFacts, rejectedPackets];
}
