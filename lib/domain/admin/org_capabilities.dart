import 'package:equatable/equatable.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

/// Operational capability flags for an organization.
/// INV-14: capability flags, not enum — transport-agnostic core.
/// NULL capabilities in DB defaults to all-true (safe migration, no client breakage).
class OrgCapabilities extends Equatable {
  final bool allowsSealing; // lacre, chk_saida categories
  final bool allowsLoading; // carregamento category
  final bool allowsCargoCheck; // generic cargo check
  final bool allowsIncident; // incidente category
  final bool allowsDoc; // doc category
  final bool smartClassify; // GPS auto-classify via EXIF geofence
  final double? maxKinematicSpeedKmh; // Physical Metric - Double Required

  const OrgCapabilities({
    this.allowsSealing = true,
    this.allowsLoading = true,
    this.allowsCargoCheck = true,
    this.allowsIncident = true,
    this.allowsDoc = true,
    this.smartClassify = true,
    this.maxKinematicSpeedKmh,
  });

  static const OrgCapabilities defaults = OrgCapabilities();

  factory OrgCapabilities.fromJson(Map<String, dynamic> json) {
    return OrgCapabilities(
      allowsSealing: _parseBool(json, 'allows_sealing', defaultValue: true),
      allowsLoading: _parseBool(json, 'allows_loading', defaultValue: true),
      allowsCargoCheck: _parseBool(
        json,
        'allows_cargo_check',
        defaultValue: true,
      ),
      allowsIncident: _parseBool(json, 'allows_incident', defaultValue: true),
      allowsDoc: _parseBool(json, 'allows_doc', defaultValue: true),
      smartClassify: _parseBool(json, 'smart_classify', defaultValue: true),
      maxKinematicSpeedKmh: _parseSpeed(
        json,
        'max_kinematic_speed_kmh',
      )?.toDouble(),
    );
  }

  /// Strict bool parser — throws [IntegrityException] if field exists but is not bool.
  static bool _parseBool(
    Map<String, dynamic> json,
    String key, {
    required bool defaultValue,
  }) {
    final value = json[key];
    if (value == null) return defaultValue;
    if (value is bool) return value;
    throw IntegrityException(
      'Field "$key" must be bool, got ${value.runtimeType}',
      field: key,
    );
  }

  /// Strict numeric parser for kinematic speed — throws [IntegrityException]
  /// if field exists but is not a num.
  static num? _parseSpeed(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is num) return value;
    throw IntegrityException(
      'Field "$key" must be num, got ${value.runtimeType}',
      field: key,
    );
  }

  Map<String, dynamic> toJson() => {
    'allows_sealing': allowsSealing,
    'allows_loading': allowsLoading,
    'allows_cargo_check': allowsCargoCheck,
    'allows_incident': allowsIncident,
    'allows_doc': allowsDoc,
    'smart_classify': smartClassify,
    if (maxKinematicSpeedKmh != null)
      'max_kinematic_speed_kmh': maxKinematicSpeedKmh,
  };

  /// Category keys that should be hidden from the evidence menu for this org.
  List<String> get hiddenCategories {
    final hidden = <String>[];
    if (!allowsSealing) hidden.addAll(['lacre', 'chk_saida']);
    if (!allowsLoading) hidden.add('carregamento');
    if (!allowsIncident) hidden.add('incidente');
    if (!allowsDoc) hidden.add('doc');
    return hidden;
  }

  OrgCapabilities copyWith({
    bool? allowsSealing,
    bool? allowsLoading,
    bool? allowsCargoCheck,
    bool? allowsIncident,
    bool? allowsDoc,
    bool? smartClassify,
    double? maxKinematicSpeedKmh, // Physical Metric - Double Required
  }) {
    return OrgCapabilities(
      allowsSealing: allowsSealing ?? this.allowsSealing,
      allowsLoading: allowsLoading ?? this.allowsLoading,
      allowsCargoCheck: allowsCargoCheck ?? this.allowsCargoCheck,
      allowsIncident: allowsIncident ?? this.allowsIncident,
      allowsDoc: allowsDoc ?? this.allowsDoc,
      smartClassify: smartClassify ?? this.smartClassify,
      maxKinematicSpeedKmh: maxKinematicSpeedKmh ?? this.maxKinematicSpeedKmh,
    );
  }

  @override
  List<Object?> get props => [
    allowsSealing,
    allowsLoading,
    allowsCargoCheck,
    allowsIncident,
    allowsDoc,
    smartClassify,
    maxKinematicSpeedKmh,
  ];
}
