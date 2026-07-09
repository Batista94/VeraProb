// pr_scanner: ignore-regression — Legal Gate LGPD consent status VO (Council-approved package)
import 'package:veraprob/domain/legal/legal_document.dart';

/// Whether the authenticated user must accept the current terms.
enum LegalConsentState {
  /// User has accepted the active published terms_of_use.
  current,

  /// User must accept (first time or after version bump / withdraw).
  pending,
}

/// Result of [ILegalConsentRepository.getConsentStatus].
class LegalConsentStatus {
  final LegalConsentState state;
  final LegalDocument? document;
  final String? priorVersion;

  const LegalConsentStatus({
    required this.state,
    this.document,
    this.priorVersion,
  });

  bool get isPending => state == LegalConsentState.pending;
  bool get isCurrent => state == LegalConsentState.current;
}
