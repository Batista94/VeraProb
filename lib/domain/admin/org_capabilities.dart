import 'package:equatable/equatable.dart';

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

  const OrgCapabilities({
    this.allowsSealing = true,
    this.allowsLoading = true,
    this.allowsCargoCheck = true,
    this.allowsIncident = true,
    this.allowsDoc = true,
    this.smartClassify = true,
  });

  static const OrgCapabilities defaults = OrgCapabilities();

  factory OrgCapabilities.fromJson(Map<String, dynamic> json) {
    return OrgCapabilities(
      allowsSealing: json['allows_sealing'] as bool? ?? true,
      allowsLoading: json['allows_loading'] as bool? ?? true,
      allowsCargoCheck: json['allows_cargo_check'] as bool? ?? true,
      allowsIncident: json['allows_incident'] as bool? ?? true,
      allowsDoc: json['allows_doc'] as bool? ?? true,
      smartClassify: json['smart_classify'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'allows_sealing': allowsSealing,
    'allows_loading': allowsLoading,
    'allows_cargo_check': allowsCargoCheck,
    'allows_incident': allowsIncident,
    'allows_doc': allowsDoc,
    'smart_classify': smartClassify,
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
  }) {
    return OrgCapabilities(
      allowsSealing: allowsSealing ?? this.allowsSealing,
      allowsLoading: allowsLoading ?? this.allowsLoading,
      allowsCargoCheck: allowsCargoCheck ?? this.allowsCargoCheck,
      allowsIncident: allowsIncident ?? this.allowsIncident,
      allowsDoc: allowsDoc ?? this.allowsDoc,
      smartClassify: smartClassify ?? this.smartClassify,
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
  ];
}
