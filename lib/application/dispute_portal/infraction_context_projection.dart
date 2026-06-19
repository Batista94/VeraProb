class InfractionContextProjection {
  final String assetIdentifier;
  final int penaltyValueCents;
  final int? measuredValue;
  final int? thresholdValue;
  final int? exceededBy;
  final DateTime occurredAtUtc;
  final String locationLabel;
  final String recordId;
  final String orgDisplayName;
  final String orgCnpj;
  final String orgLogoUrl;
  final String? clauseRef;
  final num? primaryEvidenceLat;
  final num? primaryEvidenceLng;

  const InfractionContextProjection({
    required this.assetIdentifier,
    required this.penaltyValueCents,
    this.measuredValue,
    this.thresholdValue,
    this.exceededBy,
    required this.occurredAtUtc,
    required this.locationLabel,
    required this.recordId,
    required this.orgDisplayName,
    required this.orgCnpj,
    required this.orgLogoUrl,
    this.clauseRef,
    this.primaryEvidenceLat,
    this.primaryEvidenceLng,
  });

  factory InfractionContextProjection.fromJson(Map<String, dynamic> json) {
    return InfractionContextProjection(
      assetIdentifier: json['asset_identifier'] as String,
      penaltyValueCents: json['penalty_value_cents'] as int,
      measuredValue: json['measured_value'] as int?,
      thresholdValue: json['threshold_value'] as int?,
      exceededBy: json['exceeded_by'] as int?,
      occurredAtUtc: DateTime.parse(json['occurred_at_utc'] as String).toUtc(),
      locationLabel: json['location_label'] as String,
      recordId: json['record_id'] as String,
      orgDisplayName: json['org_display_name'] as String,
      orgCnpj: json['org_cnpj'] as String,
      orgLogoUrl: json['org_logo_url'] as String,
      clauseRef: json['clause_ref'] as String?,
      primaryEvidenceLat: json['primary_evidence_lat'] as num?,
      primaryEvidenceLng: json['primary_evidence_lng'] as num?,
    );
  }
}
