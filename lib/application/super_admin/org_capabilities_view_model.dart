import 'package:veraprob/domain/admin/org_capabilities.dart';

/// Application-layer projection of [OrgCapabilities] for the presentation layer.
///
/// **INV-4 / Lens 2 boundary enforcement:**
/// - All fields are primitives (`bool`, `double?`). No domain type leaks into
///   `lib/features/`.
/// - Conversion *to* domain happens in [toDomain], which is only called from
///   within application-layer FormData DTOs (`CreateOrganizationFormData`,
///   `UpdateQuotaFormData`).
/// - Conversion *from* domain happens in [fromDomain], called from
///   `TenantHealthView.fromJson` inside the application layer.
class OrgCapabilitiesViewModel {
  final bool allowsSealing;
  final bool allowsLoading;
  final bool allowsCargoCheck;
  final bool allowsIncident;
  final bool allowsDoc;
  final bool smartClassify;

  /// Max kinematic speed (km/h). `null` means no limit configured.
  /// Physical Metric — double is correct here (speed is continuous).
  final double? maxKinematicSpeedKmh; // Physical Metric - Double Required

  const OrgCapabilitiesViewModel({
    this.allowsSealing = true,
    this.allowsLoading = true,
    this.allowsCargoCheck = true,
    this.allowsIncident = true,
    this.allowsDoc = true,
    this.smartClassify = true,
    this.maxKinematicSpeedKmh,
  });

  /// Sensible all-enabled default, mirrors [OrgCapabilities.defaults].
  static const OrgCapabilitiesViewModel defaults = OrgCapabilitiesViewModel();

  // ── Conversion boundary ───────────────────────────────────────────────────

  /// Creates a ViewModel from the domain entity.
  /// Called exclusively from application-layer factories (e.g. [TenantHealthView]).
  factory OrgCapabilitiesViewModel.fromDomain(OrgCapabilities domain) {
    return OrgCapabilitiesViewModel(
      allowsSealing: domain.allowsSealing,
      allowsLoading: domain.allowsLoading,
      allowsCargoCheck: domain.allowsCargoCheck,
      allowsIncident: domain.allowsIncident,
      allowsDoc: domain.allowsDoc,
      smartClassify: domain.smartClassify,
      maxKinematicSpeedKmh: domain.maxKinematicSpeedKmh,
    );
  }

  /// Projects this ViewModel back to the domain entity.
  /// Called exclusively from application-layer DTOs before dispatching commands.
  OrgCapabilities toDomain() {
    return OrgCapabilities(
      allowsSealing: allowsSealing,
      allowsLoading: allowsLoading,
      allowsCargoCheck: allowsCargoCheck,
      allowsIncident: allowsIncident,
      allowsDoc: allowsDoc,
      smartClassify: smartClassify,
      maxKinematicSpeedKmh: maxKinematicSpeedKmh,
    );
  }

  // ── Immutable copy ────────────────────────────────────────────────────────

  OrgCapabilitiesViewModel copyWith({
    bool? allowsSealing,
    bool? allowsLoading,
    bool? allowsCargoCheck,
    bool? allowsIncident,
    bool? allowsDoc,
    bool? smartClassify,
    double? maxKinematicSpeedKmh, // Physical Metric - Double Required
    bool clearMaxSpeed = false,
  }) {
    return OrgCapabilitiesViewModel(
      allowsSealing: allowsSealing ?? this.allowsSealing,
      allowsLoading: allowsLoading ?? this.allowsLoading,
      allowsCargoCheck: allowsCargoCheck ?? this.allowsCargoCheck,
      allowsIncident: allowsIncident ?? this.allowsIncident,
      allowsDoc: allowsDoc ?? this.allowsDoc,
      smartClassify: smartClassify ?? this.smartClassify,
      maxKinematicSpeedKmh: clearMaxSpeed
          ? null
          : (maxKinematicSpeedKmh ?? this.maxKinematicSpeedKmh),
    );
  }

  /// Returns `true` when this VM differs from [template] in any capability flag
  /// or kinematic speed. Used by the wizard to detect preset customization.
  bool isCustomized(OrgCapabilitiesViewModel template) {
    return allowsSealing != template.allowsSealing ||
        allowsLoading != template.allowsLoading ||
        allowsCargoCheck != template.allowsCargoCheck ||
        allowsIncident != template.allowsIncident ||
        allowsDoc != template.allowsDoc ||
        smartClassify != template.smartClassify ||
        maxKinematicSpeedKmh != template.maxKinematicSpeedKmh;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrgCapabilitiesViewModel &&
          allowsSealing == other.allowsSealing &&
          allowsLoading == other.allowsLoading &&
          allowsCargoCheck == other.allowsCargoCheck &&
          allowsIncident == other.allowsIncident &&
          allowsDoc == other.allowsDoc &&
          smartClassify == other.smartClassify &&
          maxKinematicSpeedKmh == other.maxKinematicSpeedKmh;

  @override
  int get hashCode => Object.hash(
    allowsSealing,
    allowsLoading,
    allowsCargoCheck,
    allowsIncident,
    allowsDoc,
    smartClassify,
    maxKinematicSpeedKmh,
  );
}
