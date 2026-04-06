import 'package:veraprob/domain/sla_audit/sla_template.dart';
import 'package:veraprob/domain/sla_audit/transport_vertical.dart';
import 'penalties_form_data.dart';

/// Flat read model for [SlaTemplate] used in presentation layer.
///
/// All financial fields use `int` (BPS or cents — INV-2).
class SlaTemplateView {
  final String id;
  final String organizationId;
  final String name;
  final String? description;
  final TransportVertical? vertical;
  final int noShowPenaltyBps;
  final int delayToleranceMinutes;
  final int delayPenaltyPerMinuteCents;
  final int downgradePenaltyFlatCents;
  final int noShowThresholdMinutes;
  final int earlyArrivalToleranceMinutes;
  final int dwellTimeMinutes;
  final int gracePeriodMinutes;
  final int baseTripValueCents;
  final DateTime createdAt;

  const SlaTemplateView({
    required this.id,
    required this.organizationId,
    required this.name,
    this.description,
    this.vertical,
    required this.noShowPenaltyBps,
    required this.delayToleranceMinutes,
    required this.delayPenaltyPerMinuteCents,
    required this.downgradePenaltyFlatCents,
    required this.noShowThresholdMinutes,
    required this.earlyArrivalToleranceMinutes,
    required this.dwellTimeMinutes,
    required this.gracePeriodMinutes,
    required this.baseTripValueCents,
    required this.createdAt,
  });

  PenaltiesFormData get penalties => PenaltiesFormData(
    noShowPenaltyBps: noShowPenaltyBps,
    delayToleranceMinutes: delayToleranceMinutes,
    delayPenaltyPerMinuteCents: delayPenaltyPerMinuteCents,
    downgradePenaltyFlatCents: downgradePenaltyFlatCents,
    noShowThresholdMinutes: noShowThresholdMinutes,
    earlyArrivalToleranceMinutes: earlyArrivalToleranceMinutes,
    dwellTimeMinutes: dwellTimeMinutes,
    gracePeriodMinutes: gracePeriodMinutes,
    baseTripValueCents: baseTripValueCents,
  );

  factory SlaTemplateView.fromDomain(SlaTemplate template) {
    return SlaTemplateView(
      id: template.id,
      organizationId: template.organizationId,
      name: template.name,
      description: template.description,
      vertical: template.vertical,
      noShowPenaltyBps: template.penalties.noShowPenaltyBps,
      delayToleranceMinutes: template.penalties.delayToleranceMinutes,
      delayPenaltyPerMinuteCents:
          template.penalties.delayPenaltyPerMinute.cents,
      downgradePenaltyFlatCents: template.penalties.downgradePenaltyFlat.cents,
      noShowThresholdMinutes: template.penalties.noShowThresholdMinutes,
      earlyArrivalToleranceMinutes:
          template.penalties.earlyArrivalToleranceMinutes,
      dwellTimeMinutes: template.penalties.dwellTimeMinutes,
      gracePeriodMinutes: template.penalties.gracePeriodMinutes,
      baseTripValueCents: template.penalties.baseTripValue.cents,
      createdAt: template.createdAt,
    );
  }
}
