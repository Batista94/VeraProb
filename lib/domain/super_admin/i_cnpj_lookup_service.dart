import 'cnpj_company_data.dart';

/// Domain interface for CNPJ lookup / enrichment.
///
/// Implementations call a public CNPJ registry API (e.g. ReceitaWS) and
/// return structured company information for auto-filling the onboarding wizard.
///
/// Returns `null` when the CNPJ is not found or the service is unavailable.
/// Never throws — callers should treat null as "no enrichment available".
///
/// **INV-4:** Interface lives in domain; implementation lives in infrastructure.
/// **INV-25:** Implementation must use a free/freemium service.
abstract class ICnpjLookupService {
  Future<CnpjCompanyData?> lookup(String cnpjDigits);
}
