import 'package:equatable/equatable.dart';

/// Represents a specific issue detected by the Situation Engine.
class OperationalWarning extends Equatable {
  final String id;
  final String type; // e.g., 'delay_critical', 'vehicle_stopped'
  final String message;
  final int severityScore;
  final DateTime detectedAt;
  final Map<String, dynamic>? metadata;

  const OperationalWarning({
    required this.id,
    required this.type,
    required this.message,
    required this.severityScore,
    required this.detectedAt,
    this.metadata,
  });

  @override
  List<Object?> get props => [
    id,
    type,
    message,
    severityScore,
    detectedAt,
    metadata,
  ];
}
