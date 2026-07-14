// pr_scanner: ignore-regression — Legal Gate LGPD domain port (Council-approved package)
import 'package:veraprob/domain/legal/legal_consent_status.dart';

/// Port for LGPD Legal Gate consent operations (Flutter auth.users).
///
/// Concrete implementation: SupabaseLegalConsentRepository.
abstract class ILegalConsentRepository {
  /// One round-trip: pending/current + active document payload.
  Future<LegalConsentStatus> getConsentStatus();

  /// Records acceptance of [documentId] (must be the active terms_of_use).
  Future<void> acceptTerms(String documentId);

  // ponytail: withdrawConsent deferred until settings UI (UAT §9); SQL RPC remains.
}
