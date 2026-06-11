import 'package:equatable/equatable.dart';

/// Value Object: a code from the global dispute_reason_codes catalogue.
/// Q2: closed global catalogue in v1.
class DisputeReasonCode extends Equatable {
  final String code;
  final String category;
  final String labelPt;
  final String labelEn;
  final bool isActive;

  const DisputeReasonCode({
    required this.code,
    required this.category,
    required this.labelPt,
    required this.labelEn,
    required this.isActive,
  });

  @override
  List<Object?> get props => [code]; // VO identity = code (correct here)
}
