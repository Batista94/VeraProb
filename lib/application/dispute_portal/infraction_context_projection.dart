import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:veraprob/domain/shared/brazil_time.dart';
import 'package:veraprob/domain/shared/coordinate.dart';
import 'package:veraprob/domain/shared/money.dart';

class InfractionContextProjection {
  final String? assetIdentifier;
  final int? penaltyValueCents;
  final int? measuredValue;
  final int? thresholdValue;
  final int? exceededBy;
  final DateTime occurredAtUtc;
  final String? locationLabel;
  final String recordId;
  final String status;
  final String? orgDisplayName;
  final String? orgCnpj;
  final String? orgLogoUrl;
  final String? clauseRef;
  final Coordinate? primaryEvidenceCoordinate;

  const InfractionContextProjection({
    this.assetIdentifier,
    this.penaltyValueCents,
    this.measuredValue,
    this.thresholdValue,
    this.exceededBy,
    required this.occurredAtUtc,
    this.locationLabel,
    required this.recordId,
    required this.status,
    this.orgDisplayName,
    this.orgCnpj,
    this.orgLogoUrl,
    this.clauseRef,
    this.primaryEvidenceCoordinate,
  });

  /// Formatted penalty value in BRL (e.g., "R$ 1.500,00").
  String get formattedPenaltyValue {
    if (penaltyValueCents == null) return '-';
    final value = Money(penaltyValueCents!).toDouble();
    return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(value);
  }

  /// Formatted occurrence date in America/Sao_Paulo timezone.
  String get formattedOccurredAtBrt {
    BrazilTime.ensureInitialized();
    final brtDate = tz.TZDateTime.from(
      occurredAtUtc,
      tz.getLocation(BrazilTime.operationalTimezone),
    );
    return DateFormat('dd/MM/yyyy HH:mm').format(brtDate);
  }

  String get formattedMeasuredValue =>
      measuredValue != null ? '$measuredValue $_unit' : '-';

  String get formattedThresholdValue =>
      thresholdValue != null ? '$thresholdValue $_unit' : '-';

  String get formattedExceededBy =>
      exceededBy != null ? '+$exceededBy $_unit' : '-';

  String get _unit {
    if (clauseRef == null) return 'unid.';
    final prefix = clauseRef!.split('-').first.toUpperCase();
    switch (prefix) {
      case 'VEL':
        return 'km/h';
      case 'ATR':
      case 'POS':
        return 'min';
      case 'ABR':
        return 'eventos';
      default:
        return 'unid.';
    }
  }

  factory InfractionContextProjection.fromJson(Map<String, dynamic> json) {
    final latNum = json['primary_evidence_lat'] as num?;
    final lngNum = json['primary_evidence_lng'] as num?;

    final double? lat = latNum?.toDouble(); // Physical Metric - Double Required
    final double? lng = lngNum?.toDouble(); // Physical Metric - Double Required

    return InfractionContextProjection(
      assetIdentifier: json['asset_identifier'] as String?,
      penaltyValueCents: json['penalty_value_cents'] as int?,
      measuredValue: json['measured_value'] as int?,
      thresholdValue: json['threshold_value'] as int?,
      exceededBy: json['exceeded_by'] as int?,
      occurredAtUtc: DateTime.parse(json['occurred_at_utc'] as String).toUtc(),
      locationLabel: json['location_label'] as String?,
      recordId: json['record_id'] as String,
      status: json['status'] as String,
      orgDisplayName: json['org_display_name'] as String?,
      orgCnpj: json['org_cnpj'] as String?,
      orgLogoUrl: json['org_logo_url'] as String?,
      clauseRef: json['clause_ref'] as String?,
      primaryEvidenceCoordinate: lat != null && lng != null
          ? Coordinate(lat, lng)
          : null,
    );
  }
}
