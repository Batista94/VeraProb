import 'package:veraprob/domain/admin/quota_warning.dart';

/// Application-layer projection of [QuotaWarning] for the presentation layer.
///
/// **INV-4 / Lens 2 boundary enforcement:**
/// All fields are primitives. The widget [OrgHealthCard] accepts this ViewModel
/// instead of the domain entity, so [QuotaWarning] is never imported in
/// `lib/features/`.
///
/// [isCritical] and [isUrgent] are computed locally to avoid leaking the
/// domain's computed properties while still keeping the rendering logic
/// outside the ViewModel (separation of concerns).
class QuotaWarningViewModel {
  final int id;
  final String organizationId;
  final String resource;
  final int usagePct;
  final int threshold;
  final int currentCount;
  final int maxAllowed;
  final DateTime triggeredAt;

  /// Whether this warning is at a critical threshold (>= 90%).
  final bool isCritical;

  /// Whether this warning is at an urgent threshold (>= 80%).
  final bool isUrgent;

  const QuotaWarningViewModel({
    required this.id,
    required this.organizationId,
    required this.resource,
    required this.usagePct,
    required this.threshold,
    required this.currentCount,
    required this.maxAllowed,
    required this.triggeredAt,
    required this.isCritical,
    required this.isUrgent,
  });

  /// Creates a ViewModel from the domain entity.
  /// Called exclusively from application-layer factories.
  factory QuotaWarningViewModel.fromDomain(QuotaWarning domain) {
    return QuotaWarningViewModel(
      id: domain.id,
      organizationId: domain.organizationId,
      resource: domain.resource,
      usagePct: domain.usagePct,
      threshold: domain.threshold,
      currentCount: domain.currentCount,
      maxAllowed: domain.maxAllowed,
      triggeredAt: domain.triggeredAt,
      isCritical: domain.isCritical,
      isUrgent: domain.isUrgent,
    );
  }
}
